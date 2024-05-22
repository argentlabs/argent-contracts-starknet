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

impl SpanU8TryIntoFelt252 of TryInto<Span<u8>, felt252> {
    fn try_into(mut self: Span<u8>) -> Option<felt252> {
        if self.len() < 32 {
            let mut result = 0;
            while let Option::Some(byte) = self
                .pop_front() {
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

// Accepts felt252 for efficiency as it's the type of retdata but all values are expected to fit u32
fn u32s_to_u256(arr: Span<felt252>) -> u256 {
    assert!(arr.len() == 8, "u32s_to_u256: input must be 8 elements long");
    let low = *arr.at(7)
        + *arr.at(6) * 0x1_0000_0000
        + *arr.at(5) * 0x1_0000_0000_0000_0000
        + *arr.at(4) * 0x1_0000_0000_0000_0000_0000_0000;
    let low = low.try_into().expect('u32s_to_u256:overflow-low');
    let high = *arr.at(3)
        + *arr.at(2) * 0x1_0000_0000
        + *arr.at(1) * 0x1_0000_0000_0000_0000
        + *arr.at(0) * 0x1_0000_0000_0000_0000_0000_0000;
    let high = high.try_into().expect('u32s_to_u256:overflow-high');
    u256 { high, low }
}

// Accepts felt252 for efficiency as it's the type of retdata but all values are expected to fit u32
fn u32s_to_u8s(mut words: Span<felt252>) -> Span<u8> {
    let mut output = array![];
    while let Option::Some(word) = words
        .pop_front() {
            let word: u32 = (*word).try_into().unwrap();
            let (rest, byte_4) = integer::u32_safe_divmod(word, 0x100);
            let (rest, byte_3) = integer::u32_safe_divmod(rest, 0x100);
            let (byte_1, byte_2) = integer::u32_safe_divmod(rest, 0x100);
            output.append(byte_1.try_into().unwrap());
            output.append(byte_2.try_into().unwrap());
            output.append(byte_3.try_into().unwrap());
            output.append(byte_4.try_into().unwrap());
        };
    output.span()
}
// Takes an array of u8s and returns an array of u32s padding the end with 0s if necessary
fn u8s_to_u32s_pad_end(mut bytes: Span<u8>) -> Array<u32> {
    let mut output = array![];
    while let Option::Some(byte1) = bytes
        .pop_front() {
            let byte1 = *byte1;
            let byte2 = *bytes.pop_front().unwrap_or_default();
            let byte3 = *bytes.pop_front().unwrap_or_default();
            let byte4 = *bytes.pop_front().unwrap_or_default();
            output.append(0x100_00_00 * byte1.into() + 0x100_00 * byte2.into() + 0x100 * byte3.into() + byte4.into());
        };
    output
}
