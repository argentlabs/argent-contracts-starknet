use alexandria_encoding::base64::Base64UrlDecoder;
use argent::common::bytes::ByteArrayExt;
use argent::signer::webauthn::decode_base64;

#[test]
#[available_gas(1_000_000_000)]
fn base64_decoding() {
    // 0xdeadbeef
    // 3q2-7w==
    let encoded: Array<u8> = "3q2-7w==".into_bytes();
    let value = Base64UrlDecoder::decode(encoded);
    assert(value == array![0xde, 0xad, 0xbe, 0xef], 'Base64 decoding failed');
}

#[test]
#[available_gas(1_000_000_000)]
fn base64_unpadded_decoding() {
    // 0xdeadbeef
    // 3q2-7w
    let encoded: Array<u8> = "3q2-7w".into_bytes();
    let value = decode_base64(encoded);
    assert(value == array![0xde, 0xad, 0xbe, 0xef], 'Base64 decoding failed');
}

#[test]
#[available_gas(1_000_000_000)]
fn base64_max_felt_decoding() {
    // CAAAAAAAABEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
    let encoded: Array<u8> = "CAAAAAAAABEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=".into_bytes();
    let value = Base64UrlDecoder::decode(encoded);

    // 0x08000000000000110000000000000000000000000000000000000000000000000
    let expected = array![
        0x08,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x11,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
    ];
    assert(value == expected, 'Base64 decoding failed');
}

