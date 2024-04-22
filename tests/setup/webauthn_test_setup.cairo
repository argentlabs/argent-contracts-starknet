use argent::signer::signer_signature::{WebauthnSigner};
use argent::signer::webauthn::{WebauthnAssertion};
use argent::utils::bytes::ByteArrayExt;
use starknet::secp256_trait::Signature;

fn new_webauthn_signer(origin: ByteArray, rp_id_hash: u256, pubkey: u256) -> WebauthnSigner {
    let origin = origin.into_bytes().span();
    let rp_id_hash = rp_id_hash.try_into().expect('argent/zero-rp-id-hash');
    let pubkey = pubkey.try_into().expect('argent/zero-pubkey');
    WebauthnSigner { origin, rp_id_hash, pubkey }
}

fn get_authenticator_data() -> Span<u8> {
    // rp id hash = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763
    // flags (binary) = 101
    // sign count = 0
    array![
        73,
        150,
        13,
        229,
        136,
        14,
        140,
        104,
        116,
        52,
        23,
        15,
        100,
        118,
        96,
        91,
        143,
        228,
        174,
        185,
        162,
        134,
        50,
        199,
        153,
        92,
        243,
        186,
        131,
        29,
        151,
        99,
        5,
        0,
        0,
        0,
        0
    ]
        .span()
}

fn setup_1() -> (felt252, WebauthnSigner, WebauthnAssertion) {
    let transaction_hash = 0x6fd6673287ba2e4d2975ad878dc26c0a989c549259d87a044a8d37bb9168bb4;
    let signer = new_webauthn_signer(
        origin: "http://localhost:5173",
        rp_id_hash: 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763,
        pubkey: 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296,
    );
    let assertion = WebauthnAssertion {
        authenticator_data: get_authenticator_data(),
        challenge: "Bv1mcyh7ouTSl1rYeNwmwKmJxUklnYegRKjTe7kWi7QB".into_bytes().span(),
        client_data_json_outro: "\",\"crossOrigin\":false}".into_bytes().span(),
        signature: Signature {
            r: 17964448168501796902021058754052023747843800978633577064976152434953556917106,
            s: 24325385074589667029100892281776352749061721889898781064305922798414532583201,
            y_parity: true,
        },
    };
    (transaction_hash, signer, assertion)
}
