use argent::signer::signer_signature::{WebauthnSigner, Signer, SignerTrait, is_valid_webauthn_signature};
use argent::signer::webauthn::WebauthnSignature;
use starknet::secp256_trait::Signature;

#[generate_trait]
impl ByteArrayExt of ByteArrayExtTrait {
    fn into_bytes(self: ByteArray) -> Array<u8> {
        let len = self.len();
        let mut output = array![];
        let mut i = 0;
        while i != len {
            output.append(self[i]);
            i += 1;
        };
        output
    }
}

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
    let transaction_hash = 0x5bcd9babc7bde1b7e104be1f3239816cf1c19cd22d5d0e29d1026cc7d0ea3e1;
    let pubkey = 0x453325eff9c4fd248737d9464bf77bf914222d169028e10217e9ee8392ea8ab4;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: ",\"crossOrigin\":false}".into_bytes().span(),
        flags: 0b00011101,
        sign_count: 0,
        ec_signature: Signature {
            r: 0xc303f24e2f6970f0cd1521c1ff6c661337e4a397a9d4b1bed732f14ddcb828cb,
            s: 0x61d2ef1fa3c30486656361c783ae91316e9e78301fbf4f173057ea868487d387,
            y_parity: false,
        },
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

    let transaction_hash = 0xdc677de9c67c30a1e1f152e9b51c7d63c5d45b19576c747dd5b31b5d2c349;
    let pubkey = 0x937567fc640ed1bbc82d124b098cef062c2b3e65a942a078dc74e46b85be6930;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: ",\"crossOrigin\":false,\"extraField\":\"random data\"}".into_bytes().span(),
        flags: 5,
        sign_count: 0,
        ec_signature: Signature {
            r: 0xb7fdfa659cbe0beb8c6723420612d884fbf795c1f7e4c53d72bae3c84d529eb2,
            s: 0x1db6fa2148ef7a34f55239ab4edc5c12777f23a022c4928d9956bc6b8652007c,
            y_parity: true,
        },
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
fn test_is_valid_webauthn_signature_sign_count() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x5915cf7b318c568b7535fdfb30c45f50b1eeac527617296ebe50e617b7333e5;
    let pubkey = 0xc7018e49d80707c1e34d1b6cefbf37e87164d922a78b33ea99813c89ca0325ea;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: array![].span(),
        flags: 5,
        sign_count: 42,
        ec_signature: Signature {
            r: 0x9574895b2b167b811118b42fe6ec515b7ccf1e4900460a5cc16b73da7094c18f,
            s: 0x69dc67ce27067ba92338e93d093e514d99711ae7ad6829764bc265ff4bad3c1e,
            y_parity: true,
        },
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, signature);
    assert!(is_valid);
}

#[test]
fn test_is_valid_webauthn_signature_flags() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x47c411e6ec5c58f84033e5a44db52c380f871c91071628df143f4876d01f6c4;
    let pubkey = 0x3da70dbf473189390d4d78255ca6b7350d0128bbc6554bf89715f929f056d6b3;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let signature = WebauthnSignature {
        client_data_json_outro: array![].span(),
        flags: 0b00010101,
        sign_count: 1,
        ec_signature: Signature {
            r: 0x11b3cfadcdb4775a38b7186751a5fd6459ca6cb37754b627cc82d56740442bfd,
            s: 0x49f351812336a5ecfdc3e507f92711187a0131a9aa4332e285c962b27832d282,
            y_parity: false,
        },
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
