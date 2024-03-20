use alexandria_encoding::base64::Base64UrlDecoder;
use alexandria_math::sha256::sha256;
use argent::utils::bytes::{SpanU8TryIntoU256, SpanU8TryIntoFelt252, extend};
use core::debug::PrintTrait;

#[test]
fn create_message_hash() {
    let authenticator_data = get_authenticator_data();
    let client_data_json = get_client_data_json();

    let client_data_hash = sha256(client_data_json);
    let mut message = authenticator_data;
    extend(ref message, @client_data_hash);
    let message_hash: u256 = sha256(message).span().try_into().expect('invalid-message-hash');
    assert_eq!(
        message_hash,
        u256 { low: 0xf6af5a3a95f9d23efc991411a4c661c6, high: 0x8b17cd9d759c752ec650f5db242c5a74 },
        "wrong hash"
    );
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

fn get_client_data_json() -> Array<u8> {
    array![
        '{',
        '"',
        't',
        'y',
        'p',
        'e',
        '"',
        ':',
        '"',
        'w',
        'e',
        'b',
        'a',
        'u',
        't',
        'h',
        'n',
        '.',
        'g',
        'e',
        't',
        '"',
        ',',
        '"',
        'c',
        'h',
        'a',
        'l',
        'l',
        'e',
        'n',
        'g',
        'e',
        '"',
        ':',
        '"',
        '3',
        'q',
        '2',
        '-',
        '7',
        '_',
        '-',
        'q',
        '"',
        ',',
        '"',
        'o',
        'r',
        'i',
        'g',
        'i',
        'n',
        '"',
        ':',
        '"',
        'h',
        't',
        't',
        'p',
        ':',
        '/',
        '/',
        'l',
        'o',
        'c',
        'a',
        'l',
        'h',
        'o',
        's',
        't',
        ':',
        '5',
        '1',
        '7',
        '3',
        '"',
        ',',
        '"',
        'c',
        'r',
        'o',
        's',
        's',
        'O',
        'r',
        'i',
        'g',
        'i',
        'n',
        '"',
        ':',
        'f',
        'a',
        'l',
        's',
        'e',
        ',',
        '"',
        'o',
        't',
        'h',
        'e',
        'r',
        '_',
        'k',
        'e',
        'y',
        's',
        '_',
        'c',
        'a',
        'n',
        '_',
        'b',
        'e',
        '_',
        'a',
        'd',
        'd',
        'e',
        'd',
        '_',
        'h',
        'e',
        'r',
        'e',
        '"',
        ':',
        '"',
        'd',
        'o',
        ' ',
        'n',
        'o',
        't',
        ' ',
        'c',
        'o',
        'm',
        'p',
        'a',
        'r',
        'e',
        ' ',
        'c',
        'l',
        'i',
        'e',
        'n',
        't',
        'D',
        'a',
        't',
        'a',
        'J',
        'S',
        'O',
        'N',
        ' ',
        'a',
        'g',
        'a',
        'i',
        'n',
        's',
        't',
        ' ',
        'a',
        ' ',
        't',
        'e',
        'm',
        'p',
        'l',
        'a',
        't',
        'e',
        '.',
        ' ',
        'S',
        'e',
        'e',
        ' ',
        'h',
        't',
        't',
        'p',
        's',
        ':',
        '/',
        '/',
        'g',
        'o',
        'o',
        '.',
        'g',
        'l',
        '/',
        'y',
        'a',
        'b',
        'P',
        'e',
        'x',
        '"',
        '}'
    ]
}
