use argent::utils::bytes::{bytes_to_u32s, eight_words_to_bytes, u256_to_u8s, u32_to_bytes, u8s_to_u32s_pad_end};
use super::test_webauthn_validation::ByteArrayExt;

#[test]
fn convert_u8s_to_u32s_pad_end() {
    let input = "localhost".into_bytes();
    let output = u8s_to_u32s_pad_end(input.span());
    let expected = array!['loca', 'lhos', 't\x00\x00\x00'];
    assert_eq!(output, expected);

    let input = "localhost:".into_bytes();
    let output = u8s_to_u32s_pad_end(input.span());
    let expected = array!['loca', 'lhos', 't:\x00\x00'];
    assert_eq!(output, expected);

    let input = "localhost:6".into_bytes();
    let output = u8s_to_u32s_pad_end(input.span());
    let expected = array!['loca', 'lhos', 't:6\x00'];
    assert_eq!(output, expected);

    let input = "localhost:69".into_bytes();
    let output = u8s_to_u32s_pad_end(input.span());
    let expected = array!['loca', 'lhos', 't:69'];
    assert_eq!(output, expected);
}

#[test]
fn convert_8_words_to_bytes() {
    let input = [0x6a09e667, 0xbb67ae85, 0x11223344, 0x55667788, 0x99aabbcc, 0xddeeff00, 0x12345678, 0x9abcdef0];
    let output = eight_words_to_bytes(input);
    let expected = [
        0x6a, 0x09, 0xe6, 0x67, 0xbb, 0x67, 0xae, 0x85, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa,
        0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0,
    ];
    assert_eq!(output.span(), expected.span());
}

#[test]
fn convert_u256_to_u8s() {
    let input = 0x06fd6673287ba2e4d2975ad878dc26c0a989c549259d87a044a8d37bb9168bb4;
    let output = u256_to_u8s(input);
    let expected = array![
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
        0xb4,
    ];
    assert_eq!(output, expected);
}


#[test]
fn test_bytes_to_u32s() {
    let input = array!['a'];
    let (output, last, rem) = bytes_to_u32s(input.span());
    assert_eq!(output, array![]);
    assert_eq!(last, 'a');
    assert_eq!(rem, 1);

    let input = array!['a', 'b'];
    let (output, last, rem) = bytes_to_u32s(input.span());
    assert_eq!(output, array![]);
    assert_eq!(last, 'ab');
    assert_eq!(rem, 2);

    let input = array!['a', 'b', 'c'];
    let (output, last, rem) = bytes_to_u32s(input.span());
    assert_eq!(output, array![]);
    assert_eq!(last, 'abc');
    assert_eq!(rem, 3);

    let input = array!['a', 'b', 'c', 'd'];
    let (output, last, rem) = bytes_to_u32s(input.span());
    assert_eq!(output, array![1633837924]);
    assert_eq!(last, 0);
    assert_eq!(rem, 0);

    let input = array!['a', 'b', 'c', 'd', 'e'];
    let (output, last, rem) = bytes_to_u32s(input.span());
    assert_eq!(output, array!['abcd']);
    assert_eq!(last, 'e');
    assert_eq!(rem, 1);

    // Array of each letter until z
    let input = array![
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
        'g',
        'h',
        'i',
        'j',
        'k',
        'l',
        'm',
        'n',
        'o',
        'p',
        'q',
        'r',
        's',
        't',
        'u',
        'v',
        'w',
        'x',
        'y',
        'z',
    ];
    let (output, last, rem) = bytes_to_u32s(input.span());
    assert_eq!(output, array!['abcd', 'efgh', 'ijkl', 'mnop', 'qrst', 'uvwx']);
    assert_eq!(last, 'yz');
    assert_eq!(rem, 2);
}


#[test]
fn test_u32_to_bytes() {
    assert_eq!(u32_to_bytes(0), [0, 0, 0, 0]);

    assert_eq!(u32_to_bytes(256), [0, 0, 1, 0]);

    assert_eq!(u32_to_bytes(257), [0, 0, 1, 1]);

    assert_eq!(u32_to_bytes(65536), [0, 1, 0, 0]);

    assert_eq!(u32_to_bytes('abcd'), ['a', 'b', 'c', 'd']);
}
