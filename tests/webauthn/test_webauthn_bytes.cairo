use argent::utils::bytes::{U256IntoSpanU8, SpanU8TryIntoFelt252, SpanU8TryIntoU256, ByteArrayExt, u8s_to_u32s};

#[test]
fn convert_bytes_to_u256_fit_128() {
    let bytes = array![84, 153, 96, 222, 88, 128, 232, 198, 135, 67, 65, 112];
    let value = bytes.span().try_into().unwrap();
    assert_eq!(value, 0x549960de5880e8c687434170_u256, "invalid");
}

#[test]
fn convert_bytes_to_u256_fit_256() {
    let bytes = array![
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
    ];
    let value = bytes.span().try_into().unwrap(); // sha256("localhost")
    assert_eq!(value, 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763_u256, "invalid");
}

#[test]
fn convert_bytes_to_felt252() {
    let bytes = array![222, 173, 190, 239,];
    let value: felt252 = bytes.span().try_into().unwrap();
    assert_eq!(value, 0xdeadbeef, "invalid");

    let bytes = array![
        222,
        173,
        190,
        239,
        222,
        173,
        190,
        239,
        222,
        173,
        190,
        239,
        222,
        173,
        190,
        239,
        222,
        173,
        190,
        239,
        222,
        173,
        190,
        239,
        222,
        173,
        190,
        239,
    ];
    let value: felt252 = bytes.span().try_into().unwrap();
    assert_eq!(value, 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, "invalid");
}

#[test]
fn convert_bytes_to_max_felt252() {
    // 0x08000000000000110000000000000000000000000000000000000000000000000
    let bytes = array![
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
    let value: felt252 = bytes.span().try_into().unwrap();
    assert_eq!(value, -1, "invalid");
}

#[test]
fn convert_u8s_to_u32s() {
    let input = "localhost".into_bytes();
    let output = u8s_to_u32s(input.span());
    assert_eq!(output, array!['loca', 'lhos', 't\x00\x00\x00'], "invalid");

    let input = "localhost:".into_bytes();
    let output = u8s_to_u32s(input.span());
    assert_eq!(output, array!['loca', 'lhos', 't:\x00\x00'], "invalid");

    let input = "localhost:6".into_bytes();
    let output = u8s_to_u32s(input.span());
    assert_eq!(output, array!['loca', 'lhos', 't:6\x00'], "invalid");

    let input = "localhost:69".into_bytes();
    let output = u8s_to_u32s(input.span());
    assert_eq!(output, array!['loca', 'lhos', 't:69'], "invalid");
}

#[test]
fn convert_u256_to_u8s() {
    let input = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763_u256;
    let output: Span<u8> = input.into();
    let expected = array![
        0x49,
        0x96,
        0x0d,
        0xe5,
        0x88,
        0x0e,
        0x8c,
        0x68,
        0x74,
        0x34,
        0x17,
        0x0f,
        0x64,
        0x76,
        0x60,
        0x5b,
        0x8f,
        0xe4,
        0xae,
        0xb9,
        0xa2,
        0x86,
        0x32,
        0xc7,
        0x99,
        0x5c,
        0xf3,
        0xba,
        0x83,
        0x1d,
        0x97,
        0x63
    ];
    assert_eq!(output, expected.span(), "invalid");
}
