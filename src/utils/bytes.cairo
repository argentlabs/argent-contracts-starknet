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
            // Not support for more than 32 bytes
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

fn u256_to_u8s(input: u256) -> Array<u8> {
    let (rest, out32) = core::integer::u128_safe_divmod(input.low, 0x100);
    let (rest, out31) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out30) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out29) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out28) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out27) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out26) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out25) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out24) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out23) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out22) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out21) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out20) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out19) = core::integer::u128_safe_divmod(rest, 0x100);
    let (out17, out18) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out16) = core::integer::u128_safe_divmod(input.high, 0x100);
    let (rest, out15) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out14) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out13) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out12) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out11) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out10) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out9) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out8) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out7) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out6) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out5) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out4) = core::integer::u128_safe_divmod(rest, 0x100);
    let (rest, out3) = core::integer::u128_safe_divmod(rest, 0x100);
    let (out1, out2) = core::integer::u128_safe_divmod(rest, 0x100);
    array![
        out1.try_into().unwrap(),
        out2.try_into().unwrap(),
        out3.try_into().unwrap(),
        out4.try_into().unwrap(),
        out5.try_into().unwrap(),
        out6.try_into().unwrap(),
        out7.try_into().unwrap(),
        out8.try_into().unwrap(),
        out9.try_into().unwrap(),
        out10.try_into().unwrap(),
        out11.try_into().unwrap(),
        out12.try_into().unwrap(),
        out13.try_into().unwrap(),
        out14.try_into().unwrap(),
        out15.try_into().unwrap(),
        out16.try_into().unwrap(),
        out17.try_into().unwrap(),
        out18.try_into().unwrap(),
        out19.try_into().unwrap(),
        out20.try_into().unwrap(),
        out21.try_into().unwrap(),
        out22.try_into().unwrap(),
        out23.try_into().unwrap(),
        out24.try_into().unwrap(),
        out25.try_into().unwrap(),
        out26.try_into().unwrap(),
        out27.try_into().unwrap(),
        out28.try_into().unwrap(),
        out29.try_into().unwrap(),
        out30.try_into().unwrap(),
        out31.try_into().unwrap(),
        out32.try_into().unwrap(),
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
fn u32s_to_u8s(mut input: Span<felt252>) -> Span<u8> {
    let mut output = array![];
    while let Option::Some(word) = input
        .pop_front() {
            let word: u32 = (*word).try_into().unwrap();
            output.append(((word / 0x100_00_00) & 0xFF).try_into().unwrap());
            output.append(((word / 0x100_00) & 0xFF).try_into().unwrap());
            output.append(((word / 0x100) & 0xFF).try_into().unwrap());
            output.append((word & 0xFF).try_into().unwrap());
        };
    output.span()
}

fn u8s_to_u32s(mut input: Span<u8>) -> Array<u32> {
    let mut output = array![];
    while let Option::Some(byte1) = input
        .pop_front() {
            let byte1 = *byte1;
            let byte2 = *input.pop_front().unwrap_or_default();
            let byte3 = *input.pop_front().unwrap_or_default();
            let byte4 = *input.pop_front().unwrap_or_default();
            output.append(0x100_00_00 * byte1.into() + 0x100_00 * byte2.into() + 0x100 * byte3.into() + byte4.into());
        };
    output
}
