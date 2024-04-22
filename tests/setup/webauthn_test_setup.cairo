use argent::signer::signer_signature::{WebauthnSigner};
use argent::signer::webauthn::{WebauthnAssertion, Sha256Implementation};
use argent::utils::bytes::{ByteArrayExt, SpanU8TryIntoFelt252};
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
    let transaction_hash = array![
        0x06,
        0xfd,
        0x66,
        0x73,
        0x28,
        0x7b,
        0xa2,
        0xe4,
        0xd2,
        0x97,
        0x5a,
        0xd8,
        0x78,
        0xdc,
        0x26,
        0xc0,
        0xa9,
        0x89,
        0xc5,
        0x49,
        0x25,
        0x9d,
        0x87,
        0xa0,
        0x44,
        0xa8,
        0xd3,
        0x7b,
        0xb9,
        0x16,
        0x8b,
        0xb4
    ]
        .span();
    let signer = new_webauthn_signer(
        origin: "http://localhost:5173",
        rp_id_hash: 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763,
        pubkey: 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296,
    );
    let assertion = WebauthnAssertion {
        authenticator_data: get_authenticator_data(),
        transaction_hash,
        sha256_implementation: Sha256Implementation::Cairo1,
        client_data_json_outro: "\",\"crossOrigin\":false}".into_bytes().span(),
        signature: Signature {
            r: 17964448168501796902021058754052023747843800978633577064976152434953556917106,
            s: 24325385074589667029100892281776352749061721889898781064305922798414532583201,
            y_parity: true,
        },
    };
    (transaction_hash.try_into().unwrap(), signer, assertion)
}
