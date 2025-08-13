use core::integer::{u128_safe_divmod, u32_safe_divmod};

pub fn u256_to_u8s(word: u256) -> Array<u8> {
    let (rest, byte_32) = u128_safe_divmod(word.low, 0x100);
    let (rest, byte_31) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_30) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_29) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_28) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_27) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_26) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_25) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_24) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_23) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_22) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_21) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_20) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_19) = u128_safe_divmod(rest, 0x100);
    let (byte_17, byte_18) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_16) = u128_safe_divmod(word.high, 0x100);
    let (rest, byte_15) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_14) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_13) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_12) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_11) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_10) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_9) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_8) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_7) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_6) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_5) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_4) = u128_safe_divmod(rest, 0x100);
    let (rest, byte_3) = u128_safe_divmod(rest, 0x100);
    let (byte_1, byte_2) = u128_safe_divmod(rest, 0x100);
    array![
        byte_1.try_into().unwrap(),
        byte_2.try_into().unwrap(),
        byte_3.try_into().unwrap(),
        byte_4.try_into().unwrap(),
        byte_5.try_into().unwrap(),
        byte_6.try_into().unwrap(),
        byte_7.try_into().unwrap(),
        byte_8.try_into().unwrap(),
        byte_9.try_into().unwrap(),
        byte_10.try_into().unwrap(),
        byte_11.try_into().unwrap(),
        byte_12.try_into().unwrap(),
        byte_13.try_into().unwrap(),
        byte_14.try_into().unwrap(),
        byte_15.try_into().unwrap(),
        byte_16.try_into().unwrap(),
        byte_17.try_into().unwrap(),
        byte_18.try_into().unwrap(),
        byte_19.try_into().unwrap(),
        byte_20.try_into().unwrap(),
        byte_21.try_into().unwrap(),
        byte_22.try_into().unwrap(),
        byte_23.try_into().unwrap(),
        byte_24.try_into().unwrap(),
        byte_25.try_into().unwrap(),
        byte_26.try_into().unwrap(),
        byte_27.try_into().unwrap(),
        byte_28.try_into().unwrap(),
        byte_29.try_into().unwrap(),
        byte_30.try_into().unwrap(),
        byte_31.try_into().unwrap(),
        byte_32.try_into().unwrap(),
    ]
}

/// @notice Converts of 8 u32s into a u256
/// @param words 8 words sorted from most significant to least significant
/// @return u256 A 256-bit unsigned integer
pub fn eight_words_to_u256(words: [u32; 8]) -> u256 {
    let [word_0, word_1, word_2, word_3, word_4, word_5, word_6, word_7] = words;
    let high: felt252 = word_3.into()
        + word_2.into() * 0x1_0000_0000
        + word_1.into() * 0x1_0000_0000_0000_0000
        + word_0.into() * 0x1_0000_0000_0000_0000_0000_0000;
    let high: u128 = high.try_into().expect('eight_words_to_u256:overflow-hi');
    let low: felt252 = word_7.into()
        + word_6.into() * 0x1_0000_0000
        + word_5.into() * 0x1_0000_0000_0000_0000
        + word_4.into() * 0x1_0000_0000_0000_0000_0000_0000;
    let low: u128 = low.try_into().expect('eight_words_to_u256:overflow-lo');

    u256 { high, low }
}

/// @notice Converts a u32 into 4 u8s
/// @param word The u32 to convert.
/// @return The individual `u8` bytes ordered from most significant to least.
pub fn u32_to_bytes(word: u32) -> [u8; 4] {
    let (rest, byte_4) = u32_safe_divmod(word, 0x100);
    let (rest, byte_3) = u32_safe_divmod(rest, 0x100);
    let (byte_1, byte_2) = u32_safe_divmod(rest, 0x100);
    [byte_1.try_into().unwrap(), byte_2.try_into().unwrap(), byte_3.try_into().unwrap(), byte_4.try_into().unwrap()]
}

/// @notice Converts 8 32-bit words into 32 bytes.
/// @param words The 8 32-bit words to convert, ordered from most significant to least.
/// @return The individual `u8` bytes ordered from most significant to least.
pub fn eight_words_to_bytes(words: [u32; 8]) -> [u8; 32] {
    let [word_0, word_1, word_2, word_3, word_4, word_5, word_6, word_7] = words;
    let (rest, byte_0_4) = u32_safe_divmod(word_0, 0x100);
    let (rest, byte_0_3) = u32_safe_divmod(rest, 0x100);
    let (byte_0_1, byte_0_2) = u32_safe_divmod(rest, 0x100);
    let (rest, byte_1_4) = u32_safe_divmod(word_1, 0x100);
    let (rest, byte_1_3) = u32_safe_divmod(rest, 0x100);
    let (byte_1_1, byte_1_2) = u32_safe_divmod(rest, 0x100);
    let (rest, byte_2_4) = u32_safe_divmod(word_2, 0x100);
    let (rest, byte_2_3) = u32_safe_divmod(rest, 0x100);
    let (byte_2_1, byte_2_2) = u32_safe_divmod(rest, 0x100);
    let (rest, byte_3_4) = u32_safe_divmod(word_3, 0x100);
    let (rest, byte_3_3) = u32_safe_divmod(rest, 0x100);
    let (byte_3_1, byte_3_2) = u32_safe_divmod(rest, 0x100);
    let (rest, byte_4_4) = u32_safe_divmod(word_4, 0x100);
    let (rest, byte_4_3) = u32_safe_divmod(rest, 0x100);
    let (byte_4_1, byte_4_2) = u32_safe_divmod(rest, 0x100);
    let (rest, byte_5_4) = u32_safe_divmod(word_5, 0x100);
    let (rest, byte_5_3) = u32_safe_divmod(rest, 0x100);
    let (byte_5_1, byte_5_2) = u32_safe_divmod(rest, 0x100);
    let (rest, byte_6_4) = u32_safe_divmod(word_6, 0x100);
    let (rest, byte_6_3) = u32_safe_divmod(rest, 0x100);
    let (byte_6_1, byte_6_2) = u32_safe_divmod(rest, 0x100);
    let (rest, byte_7_4) = u32_safe_divmod(word_7, 0x100);
    let (rest, byte_7_3) = u32_safe_divmod(rest, 0x100);
    let (byte_7_1, byte_7_2) = u32_safe_divmod(rest, 0x100);
    [
        byte_0_1.try_into().unwrap(), byte_0_2.try_into().unwrap(), byte_0_3.try_into().unwrap(),
        byte_0_4.try_into().unwrap(), byte_1_1.try_into().unwrap(), byte_1_2.try_into().unwrap(),
        byte_1_3.try_into().unwrap(), byte_1_4.try_into().unwrap(), byte_2_1.try_into().unwrap(),
        byte_2_2.try_into().unwrap(), byte_2_3.try_into().unwrap(), byte_2_4.try_into().unwrap(),
        byte_3_1.try_into().unwrap(), byte_3_2.try_into().unwrap(), byte_3_3.try_into().unwrap(),
        byte_3_4.try_into().unwrap(), byte_4_1.try_into().unwrap(), byte_4_2.try_into().unwrap(),
        byte_4_3.try_into().unwrap(), byte_4_4.try_into().unwrap(), byte_5_1.try_into().unwrap(),
        byte_5_2.try_into().unwrap(), byte_5_3.try_into().unwrap(), byte_5_4.try_into().unwrap(),
        byte_6_1.try_into().unwrap(), byte_6_2.try_into().unwrap(), byte_6_3.try_into().unwrap(),
        byte_6_4.try_into().unwrap(), byte_7_1.try_into().unwrap(), byte_7_2.try_into().unwrap(),
        byte_7_3.try_into().unwrap(), byte_7_4.try_into().unwrap(),
    ]
}

/// @notice Converts a span of 8-bit bytes into an array of u32
/// @param arr A span of `u8` bytes, where each group of 4 bytes is combined into a single `u32` value.
/// @return (Array<u32>, u32, u32) Returns a tuple with three values:
///     - An array of `u32` values, each derived from a group of 4 bytes in the input.
///     - A `u32` representing any remaining bytes that couldn’t form a full 32-bit word.
///     - A `u32` remainder count, indicating the number of bytes left ungrouped.
///
/// @dev This function takes each set of 4 bytes from `arr` and combines them, from most significant
///     to least significant, into a `u32`. If the length of `arr` is not a multiple of 4, the final
///     `u32` and remainder count represent any leftover bytes.
// Inspired from https://github.com/starkware-libs/cairo/blob/main/corelib/src/sha256.cairo
pub fn bytes_to_u32s(arr: Span<u8>) -> (Array<u32>, u32, u32) {
    let mut word_arr: Array<u32> = array![];
    let len = arr.len();
    let rem = len % 4;
    let mut index = 0;
    let rounded_len = len - rem;
    while index != rounded_len {
        let word = (*arr.at(index + 3)).into()
            + (*arr.at(index + 2)).into() * 0x100
            + (*arr.at(index + 1)).into() * 0x10000
            + (*arr.at(index)).into() * 0x1000000;
        word_arr.append(word);
        index = index + 4;
    };
    let last = match rem {
        0 => 0_u32,
        1 => (*arr.at(len - 1)).into(),
        2 => (*arr.at(len - 1)).into() + (*arr.at(len - 2)).into() * 0x100,
        _ => (*arr.at(len - 1)).into() + (*arr.at(len - 2)).into() * 0x100 + (*arr.at(len - 3)).into() * 0x10000,
    };
    (word_arr, last, rem)
}
