use argent::signer::signer_signature::{WebauthnSigner, is_valid_webauthn_signature};
use argent::signer::webauthn::WebauthnSignature;
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

fn valid_signer() -> (felt252, WebauthnSigner, WebauthnSignature) {
    let (origin, rp_id_hash) = localhost_rp();
    let transaction_hash = 0x6dbf8822f809eee3d1f7d5abd33e32b0380196fc1ccedbb771b480038130fb1;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: array![].span(),
        flags: 0b00000101,
        sign_count: 0,
        ec_signature: Signature {
            r: 0x623acaf39fee66be3483de2b14edb79dc11e574631c7c37e9f2a8cd8d3ae604d,
            s: 0x73727597187ca2425593f2909de9186217247fe4a53341e26fcdec5aaa5fa060,
            y_parity: true,
        },
    };
    (transaction_hash, signer, signature)
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

    let transaction_hash = 0x6dbf8822f809eee3d1f7d5abd33e32b0380196fc1ccedbb771b480038130fb1;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: ",\"crossOrigin\":false,\"extraField\":\"random data\"}".into_bytes().span(),
        flags: 0b00000101,
        sign_count: 0,
        ec_signature: Signature {
            r: 0xa0924ebc244ed2921e2a217ae51abee4995f291e48f7be5d5d0186df5fdbd704,
            s: 0x292e29871323cc78d404d737bf8f9f4b34e541d27e0dda5e0fcc471ae53e6ecf,
            y_parity: true,
        },
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
fn test_is_valid_webauthn_signature_sign_count() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x6dbf8822f809eee3d1f7d5abd33e32b0380196fc1ccedbb771b480038130fb1;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: array![].span(),
        flags: 0b00000101,
        sign_count: 42,
        ec_signature: Signature {
            r: 0xe82c6bb7ff7ad43fd4b7ffe8ec7eead60cd1632b22c5bc61528c1bcbae9cbd6d,
            s: 0x31785e4243ed76930c8b2da00f46889c2918f8627b050456eb62d48e6c0ccc26,
            y_parity: false,
        },
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
fn test_is_valid_webauthn_signature_flags() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x6dbf8822f809eee3d1f7d5abd33e32b0380196fc1ccedbb771b480038130fb1;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: array![].span(),
        flags: 0b00010101,
        sign_count: 0,
        ec_signature: Signature {
            r: 0x90bf87412855adcc72a80c5cd8d6bd0e5324967bfb3f9e5527474b70774e6198,
            s: 0x3f6c70fb8ba58537a403bbe7df6402c6ef339e71fa5f494055f63567114522fb,
            y_parity: true,
        },
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
#[should_panic(expected: "webauthn/missing-user-bit")]
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
