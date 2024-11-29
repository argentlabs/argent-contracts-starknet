use argent::signer::signer_signature::{WebauthnSigner, Signer, SignerTrait, is_valid_webauthn_signature};
use argent::signer::webauthn::{WebauthnSignature, Sha256Implementation};
use argent::utils::bytes::ByteArrayExt;
use starknet::secp256_trait::Signature;

fn new_webauthn_signer(origin: ByteArray, rp_id_hash: u256, pubkey: u256) -> WebauthnSigner {
    let origin = origin.into_bytes().span();
    let rp_id_hash = rp_id_hash.try_into().expect('argent/zero-rp-id-hash');
    let pubkey = pubkey.try_into().expect('argent/zero-pubkey');
    WebauthnSigner { origin, rp_id_hash, pubkey }
}

fn localhost_rp() -> (ByteArray, u256) {
    let origin = "http://localhost:5173";
    let rp_id_hash = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763; // sha256("localhost")
    (origin, rp_id_hash)
}

// Do we need Cairo0 test?
fn valid_signer() -> (felt252, WebauthnSigner, WebauthnSignature) {
    let (origin, rp_id_hash) = localhost_rp();
    let transaction_hash = 0x39af7d31aef39f23ef1a85c6fe9afe12721dfcc631d67e35cd84e7228b69351;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: array![].span(),
        flags: 0b00000101,
        sign_count: 0,
        ec_signature: Signature {
            r: 0x1613705b475a0962ccf245fe0025a969eb202a25a4a534d3fdca804ccc682e5,
            s: 0x4d9f083d5af539ffd77752d27d14478a2381c40ab7a1d5579642ef506d5634e5,
            y_parity: true,
        },
        sha256_implementation: Sha256Implementation::Cairo1,
    };
    (transaction_hash, signer, signature)
}

#[test]
fn test_webauthn_guid() {
    let origin = "http://localhost:5173";
    let rp_id_hash = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763; // sha256("localhost")
    let pubkey = 0xaaa7d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898caaa;
    let signer = Signer::Webauthn(new_webauthn_signer(:origin, :rp_id_hash, :pubkey));
    assert_eq!(signer.into_guid(), 373364643267162427145230563325562902896349593487311671217063963547709994471);
}

#[test]
fn test_is_valid_webauthn_signature() {
    let (transaction_hash, signer, mut signature) = valid_signer();
    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
fn test_is_valid_webauthn_signature_with_extra_json() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x39af7d31aef39f23ef1a85c6fe9afe12721dfcc631d67e35cd84e7228b69351;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: ",\"crossOrigin\":false,\"extraField\":\"random data\"}".into_bytes().span(),
        flags: 0b00000101,
        sign_count: 0,
        ec_signature: Signature {
            r: 0xf490b9f47ade1c8afc3e717539dd4283a1e70e352d70a419c013d2d1476657df,
            s: 0x5c199f5dfd34fcc0a50885e04f866652e840e659dbeaa6ff061dba632b66811c,
            y_parity: false,
        },
        sha256_implementation: Sha256Implementation::Cairo1,
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
fn test_is_valid_webauthn_signature_sign_count() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x39af7d31aef39f23ef1a85c6fe9afe12721dfcc631d67e35cd84e7228b69351;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: array![].span(),
        flags: 0b00000101,
        sign_count: 42,
        ec_signature: Signature {
            r: 0x2a6d6328d71fc63d965b086807fac5cc2c1dec107842af9e647dcffe015fe95b,
            s: 0x21210e7fe1fb13c5113a12a852129720fdf7442903fac9f680e05b3471815c9a,
            y_parity: true,
        },
        sha256_implementation: Sha256Implementation::Cairo1,
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
fn test_is_valid_webauthn_signature_flags() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x39af7d31aef39f23ef1a85c6fe9afe12721dfcc631d67e35cd84e7228b69351;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: array![].span(),
        flags: 0b00010101,
        sign_count: 0,
        ec_signature: Signature {
            r: 0x998c76cc9384d7ae62f6033d60b8bae4c3f51dcde891bde3cfd6c2550b520db8,
            s: 0x47f25bc61533e0928c69fa4d907e8af6849db19ec86c43f6faa64584c80afd3a,
            y_parity: true,
        },
        sha256_implementation: Sha256Implementation::Cairo1,
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
#[should_panic(expected: "webauthn/nonpresent-user")]
fn test_invalid_webauthn_signature_missing_user_bit() {
    let (transaction_hash, signer, mut signature) = valid_signer();
    signature.flags = 0b00000000;
    let _ = is_valid_webauthn_signature(transaction_hash, signer, signature);
}

#[test]
fn test_invalid_webauthn_signature_hash() {
    let (transaction_hash, signer, mut signature) = valid_signer();
    signature.ec_signature.r = 0xdeadbeef;
    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(!is_valid);
}
