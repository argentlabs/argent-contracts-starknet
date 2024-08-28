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
    let transaction_hash = 0x712f08b474e11487440bfec6e63c1eb789271a56e78d0fad789cc858e56dd74;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        cross_origin: Option::Some(false),
        client_data_json_outro: array![].span(),
        flags: 0b00000101,
        sign_count: 0,
        ec_signature: Signature {
            r: 62165181786056207695203164583396665139812149407667633969577140813177092451787,
            s: 18605387797315088936067001631414996583299145786676774688642855838935314927861,
            y_parity: false,
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

    let transaction_hash = 0x3ce2bf63571491fd65c8e53e33b0c2ecc7e487f9dba295339db38d689e3b5ca;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        cross_origin: Option::Some(true),
        client_data_json_outro: ",\"extraField\":\"random data\"}".into_bytes().span(),
        flags: 0b00010101,
        sign_count: 42,
        ec_signature: Signature {
            r: 19670870023840550315885474235507956766557476217277073407643822104794216096240,
            s: 5663432275202665149057612808730096627589839396996609159142560785302022469931,
            y_parity: false,
        },
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
fn test_is_valid_webauthn_signature_with_cross_origin_none() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x48a14cd24aae2d3a4011ae01249efee7b38a623d3a690c156ddb456213993e4;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        cross_origin: Option::None,
        client_data_json_outro: array![].span(),
        flags: 0b00010101,
        sign_count: 42,
        ec_signature: Signature {
            r: 86355542119903718425399464977228783179424105137305434309441087583578891109274,
            s: 47907691063703130173044052464744718057219140251481677102916922869716643734432,
            y_parity: false,
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
