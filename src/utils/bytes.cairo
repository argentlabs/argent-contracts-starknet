/// @dev Leading zeros are ignored and the input must be at most 32 bytes long (both [1] and [0, 1] will be casted to 1)
impl SpanU8TryIntoU256 of TryInto<Span<u8>, u256> {
    fn try_into(mut self: Span<u8>) -> Option<u256> {
        if self.len() < 32 {
            let result: felt252 = self.try_into().unwrap();
            Option::Some(result.into())
        } else if self.len() == 32 {
            let higher_bytes: felt252 = self.slice(0, 31).try_into().unwrap();
            let last_byte = *self.at(31);
            Option::Some((0x100 * higher_bytes.into()) + last_byte.into())
        } else {
            Option::None
        }
    }
}

/// @dev Leading zeros are ignored and the input must be at most 32 bytes long (both [1] and [0, 1] will be casted to 1)
impl SpanU8TryIntoFelt252 of TryInto<Span<u8>, felt252> {
    fn try_into(mut self: Span<u8>) -> Option<felt252> {
        if self.len() < 32 {
            let mut result = 0;
            while let Option::Some(byte) = self.pop_front() {
                let byte = (*byte).into();
                result = (0x100 * result) + byte;
            };
            Option::Some(result)
        } else if self.len() == 32 {
            let result: u256 = self.try_into()?;
            Option::Some(result.try_into()?)
        } else {
            Option::None
        }
    }
}

fn u256_to_u8s(word: u256) -> Array<u8> {
    let (rest, byte_32) = integer::u128_safe_divmod(word.low, 0x100);
    let (rest, byte_31) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_30) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_29) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_28) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_27) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_26) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_25) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_24) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_23) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_22) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_21) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_20) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_19) = integer::u128_safe_divmod(rest, 0x100);
    let (byte_17, byte_18) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_16) = integer::u128_safe_divmod(word.high, 0x100);
    let (rest, byte_15) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_14) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_13) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_12) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_11) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_10) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_9) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_8) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_7) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_6) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_5) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_4) = integer::u128_safe_divmod(rest, 0x100);
    let (rest, byte_3) = integer::u128_safe_divmod(rest, 0x100);
    let (byte_1, byte_2) = integer::u128_safe_divmod(rest, 0x100);
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

#[generate_trait]
impl ByteArrayExt of ByteArrayExtTrait {
    fn into_bytes(self: ByteArray) -> Array<u8> {
        let len = self.len();
        let mut output = array![];
        let mut i = 0;
        while i != len {
            output.append(self[i]);
            i += 1;
        };
        output
    }
}

/// @notice Converts of 8 u32s into a u256
/// @param words 8 words sorted from most significant to least significant
/// @return u256 A 256-bit unsigned integer
fn eight_words_to_u256(words: [u32; 8]) -> u256 {
    let [word_0, word_1, word_2, word_3, word_4, word_5, word_6, word_7] = words;
    let high: felt252 = word_3.into()
        + word_2.into() * 0x1_0000_0000
        + word_1.into() * 0x1_0000_0000_0000_0000
        + word_0.into() * 0x1_0000_0000_0000_0000_0000_0000;
    let high: u128 = high.try_into().expect('span_to_u256:overflow-high');
    let low: felt252 = word_7.into()
        + word_6.into() * 0x1_0000_0000
        + word_5.into() * 0x1_0000_0000_0000_0000
        + word_4.into() * 0x1_0000_0000_0000_0000_0000_0000;
    let low: u128 = low.try_into().expect('span_to_u256:overflow-low');

    u256 { high, low }
}

/// @notice Converts 8 32-bit words into 32 bytes.
/// @param words The 8 32-bit words to convert, ordered from most significant to least.
/// @return The individual `u8` bytes ordered from most significant to least.
fn eight_words_to_bytes(words: [u32; 8]) -> [u8; 32] {
    let [word_0, word_1, word_2, word_3, word_4, word_5, word_6, word_7] = words;
    let (rest, byte_0_4) = integer::u32_safe_divmod(word_0, 0x100);
    let (rest, byte_0_3) = integer::u32_safe_divmod(rest, 0x100);
    let (byte_0_1, byte_0_2) = integer::u32_safe_divmod(rest, 0x100);
    let (rest, byte_1_4) = integer::u32_safe_divmod(word_1, 0x100);
    let (rest, byte_1_3) = integer::u32_safe_divmod(rest, 0x100);
    let (byte_1_1, byte_1_2) = integer::u32_safe_divmod(rest, 0x100);
    let (rest, byte_2_4) = integer::u32_safe_divmod(word_2, 0x100);
    let (rest, byte_2_3) = integer::u32_safe_divmod(rest, 0x100);
    let (byte_2_1, byte_2_2) = integer::u32_safe_divmod(rest, 0x100);
    let (rest, byte_3_4) = integer::u32_safe_divmod(word_3, 0x100);
    let (rest, byte_3_3) = integer::u32_safe_divmod(rest, 0x100);
    let (byte_3_1, byte_3_2) = integer::u32_safe_divmod(rest, 0x100);
    let (rest, byte_4_4) = integer::u32_safe_divmod(word_4, 0x100);
    let (rest, byte_4_3) = integer::u32_safe_divmod(rest, 0x100);
    let (byte_4_1, byte_4_2) = integer::u32_safe_divmod(rest, 0x100);
    let (rest, byte_5_4) = integer::u32_safe_divmod(word_5, 0x100);
    let (rest, byte_5_3) = integer::u32_safe_divmod(rest, 0x100);
    let (byte_5_1, byte_5_2) = integer::u32_safe_divmod(rest, 0x100);
    let (rest, byte_6_4) = integer::u32_safe_divmod(word_6, 0x100);
    let (rest, byte_6_3) = integer::u32_safe_divmod(rest, 0x100);
    let (byte_6_1, byte_6_2) = integer::u32_safe_divmod(rest, 0x100);
    let (rest, byte_7_4) = integer::u32_safe_divmod(word_7, 0x100);
    let (rest, byte_7_3) = integer::u32_safe_divmod(rest, 0x100);
    let (byte_7_1, byte_7_2) = integer::u32_safe_divmod(rest, 0x100);
    [
        byte_0_1.try_into().unwrap(),
        byte_0_2.try_into().unwrap(),
        byte_0_3.try_into().unwrap(),
        byte_0_4.try_into().unwrap(),
        byte_1_1.try_into().unwrap(),
        byte_1_2.try_into().unwrap(),
        byte_1_3.try_into().unwrap(),
        byte_1_4.try_into().unwrap(),
        byte_2_1.try_into().unwrap(),
        byte_2_2.try_into().unwrap(),
        byte_2_3.try_into().unwrap(),
        byte_2_4.try_into().unwrap(),
        byte_3_1.try_into().unwrap(),
        byte_3_2.try_into().unwrap(),
        byte_3_3.try_into().unwrap(),
        byte_3_4.try_into().unwrap(),
        byte_4_1.try_into().unwrap(),
        byte_4_2.try_into().unwrap(),
        byte_4_3.try_into().unwrap(),
        byte_4_4.try_into().unwrap(),
        byte_5_1.try_into().unwrap(),
        byte_5_2.try_into().unwrap(),
        byte_5_3.try_into().unwrap(),
        byte_5_4.try_into().unwrap(),
        byte_6_1.try_into().unwrap(),
        byte_6_2.try_into().unwrap(),
        byte_6_3.try_into().unwrap(),
        byte_6_4.try_into().unwrap(),
        byte_7_1.try_into().unwrap(),
        byte_7_2.try_into().unwrap(),
        byte_7_3.try_into().unwrap(),
        byte_7_4.try_into().unwrap(),
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
fn bytes_to_u32s(mut arr: Span<u8>) -> (Array<u32>, u32, u32) {
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

// Takes an array of u8s and returns an array of u32s, padding the end with 0s if necessary
fn u8s_to_u32s_pad_end(mut bytes: Span<u8>) -> Array<u32> {
    let mut output = array![];
    while let Option::Some(byte1) = bytes.pop_front() {
        let byte1 = *byte1;
        let byte2 = *bytes.pop_front().unwrap_or_default();
        let byte3 = *bytes.pop_front().unwrap_or_default();
        let byte4 = *bytes.pop_front().unwrap_or_default();
        output.append(0x100_00_00 * byte1.into() + 0x100_00 * byte2.into() + 0x100 * byte3.into() + byte4.into());
    };
    output
}
