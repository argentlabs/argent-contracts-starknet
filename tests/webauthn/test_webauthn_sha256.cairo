use alexandria_encoding::base64::Base64UrlDecoder;
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{
    ArrayU8Ext, ByteArrayExt, SpanU8TryIntoFelt252, SpanU8TryIntoU256, u32s_to_byte_array, u32s_typed_to_u256,
};
use core::byte_array::{ByteArray, ByteArrayTrait};
use core::sha256::compute_sha256_byte_array;

#[test]
fn create_message_hash() {
    let authenticator_data = get_authenticator_data().span().into_byte_array();
    let client_data_json: ByteArray =
        "{\"type\":\"webauthn.get\",\"challenge\":\"3q2-7_-q\",\"origin\":\"http://localhost:5173\",\"crossOrigin\":false,\"other_keys_can_be_added_here\":\"do not compare clientDataJSON against a template. See https://goo.gl/yabPex\"}";

    let client_data_hash = compute_sha256_byte_array(@client_data_json).span();
    let message_with_hash = ByteArrayTrait::concat(@authenticator_data, @u32s_to_byte_array(client_data_hash));
    let message_hash: u256 = u32s_typed_to_u256(@compute_sha256_byte_array(@message_with_hash));
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
        0,
    ]
}
