use argent::common::bytes::{SpanU8TryIntoFelt252, SpanU8TryIntoU256};

#[test]
#[available_gas(1_000_000_000)]
fn convert_bytes_to_u256_fit_128() {
    let bytes = array![84, 153, 96, 222, 88, 128, 232, 198, 135, 67, 65, 112];
    let value = bytes.span().try_into().unwrap();
    assert(value == 0x549960de5880e8c687434170_u256, 'invalid');
}

#[test]
#[available_gas(1_000_000_000)]
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
    assert(value == 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763_u256, 'invalid');
}

#[test]
#[available_gas(1_000_000_000)]
fn convert_bytes_to_felt252() {
    let bytes = array![222, 173, 190, 239,];
    let value: felt252 = bytes.span().try_into().unwrap();
    assert(value == 0xdeadbeef, 'invalid');

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
    assert(value == 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, 'invalid');
}

#[test]
#[available_gas(1_000_000_000)]
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
    assert(value == -1, 'invalid');
}
