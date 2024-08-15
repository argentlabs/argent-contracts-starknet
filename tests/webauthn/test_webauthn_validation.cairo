use argent::signer::signer_signature::{WebauthnSigner, is_valid_webauthn_signature};
use argent::signer::webauthn::{WebauthnSignature, Sha256Implementation};
use argent::utils::bytes::{ByteArrayExt, SpanU8TryIntoFelt252};
use starknet::secp256_trait::Signature;

fn new_webauthn_signer(origin: ByteArray, rp_id_hash: u256, pubkey: u256) -> WebauthnSigner {
    let origin = origin.into_bytes().span();
    let rp_id_hash = rp_id_hash.try_into().expect('argent/zero-rp-id-hash');
    let pubkey = pubkey.try_into().expect('argent/zero-pubkey');
    WebauthnSigner { origin, rp_id_hash, pubkey }
}

fn localhost_rp() -> (ByteArray, u256) {
    let origin = "http://localhost:5173";
    let rp_id_hash =
        0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763; // sha256("localhost")
    (origin, rp_id_hash)
}

fn valid_signer() -> (felt252, WebauthnSigner, WebauthnSignature) {
    let (origin, rp_id_hash) = localhost_rp();
    let transaction_hash = 0x06fd6673287ba2e4d2975ad878dc26c0a989c549259d87a044a8d37bb9168bb4;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        cross_origin: Option::Some(false),
        top_origin: array![].span(),
        client_data_json_outro: array![].span(),
        flags: 0b00000101,
        sign_count: 0,
        ec_signature: Signature {
            r: 0x27b78470673308c9e7ef6d9cb4fbf74b892f9e3826b515333d721cb8385cfb72,
            s: 0x35c7ae175d75e09b1907f4232c88bfd69b7c9d7f32b4b2d392a6a95324a61f21,
            y_parity: true,
        },
        sha256_implementation: Sha256Implementation::Cairo1,
    };
    (transaction_hash, signer, signature)
}


#[test]
fn test_is_valid_webauthn_signature() {
    let (transaction_hash, signer, mut signature) = valid_signer();
    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid, "invalid");
}

#[test]
fn test_is_valid_webauthn_signature_with_extra_json() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x5f7154b851dc016f851672905d64360fb098c8fd7417d1dd1e83aa46eb6d363;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        cross_origin: Option::Some(true),
        top_origin: array![].span(),
        client_data_json_outro: ",\"extraField\":\"random data\"}".into_bytes().span(),
        flags: 0b00010101,
        sign_count: 42,
        ec_signature: Signature {
            r: 0x5cceed8562c156cb79e222afc5fd95b57a3c732795fb9b315582c57e8017f277,
            s: 0x3cedd77bd9069c8b250f6a435cce5a379257b18daf7c81136c5ca3075824b68f,
            y_parity: false,
        },
        sha256_implementation: Sha256Implementation::Cairo1,
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid, "invalid");
}

#[test]
#[should_panic(expected: "webauthn/nonpresent-user")]
fn test_invalid_webauthn_signature_nonpresent_user() {
    let (transaction_hash, signer, mut signature) = valid_signer();
    signature.flags = 0b00000000;
    is_valid_webauthn_signature(transaction_hash, signer, signature);
}

#[test]
fn test_invalid_webauthn_signature_hash() {
    let (transaction_hash, signer, mut signature) = valid_signer();
    signature.ec_signature.r = 0xdeadbeef;
    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(!is_valid, "invalid");
}
