use alexandria_math::sha256::sha256;
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{ByteArrayExt, SpanU8TryIntoU256};

#[test]
fn create_message_hash() {
    let authenticator_data = get_authenticator_data();
    let client_data_json =
        "{\"type\":\"webauthn.get\",\"challenge\":\"3q2-7_-q\",\"origin\":\"http://localhost:5173\",\"crossOrigin\":false,\"other_keys_can_be_added_here\":\"do not compare clientDataJSON against a template. See https://goo.gl/yabPex\"}"
        .into_bytes();

    let client_data_hash = sha256(client_data_json).span();
    let mut message = authenticator_data;
    message.append_all(client_data_hash);
    let message_hash: u256 = sha256(message).span().try_into().expect('invalid-message-hash');
    assert_eq!(message_hash, 0x8b17cd9d759c752ec650f5db242c5a74f6af5a3a95f9d23efc991411a4c661c6, "wrong hash");
}

fn get_authenticator_data() -> Array<u8> {
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
}
