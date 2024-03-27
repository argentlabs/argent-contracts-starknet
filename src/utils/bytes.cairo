fn extend(ref arr: Array<u8>, src: @Array<u8>) {
    let mut src = src.span();
    while let Option::Some(byte) = src.pop_front() {
        arr.append(*byte);
    };
}

impl SpanU8TryIntoU256 of TryInto<Span<u8>, u256> {
    fn try_into(mut self: Span<u8>) -> Option<u256> {
        if self.len() > 32 {
            return Option::None;
        }
        let mut result = 0;
        while let Option::Some(byte) = self.pop_front() {
            result = result * 0x100 + (*byte).into();
        };
        Option::Some(result)
    }
}

impl SpanU8TryIntoFelt252 of TryInto<Span<u8>, felt252> {
    fn try_into(mut self: Span<u8>) -> Option<felt252> {
        // TODO: check if it shouldn't be 31
        if self.len() > 32 {
            return Option::None;
        }
        let mut result = 0;
        while let Option::Some(byte) = self.pop_front() {
            result = result * 0x100 + (*byte).into();
        };
        Option::Some(result)
    }
}

impl U256IntoSpanU8 of Into<u256, Span<u8>> {
    fn into(mut self: u256) -> Span<u8> {
        let shift = integer::u256_as_non_zero(0x100);
        let (rest, out32) = integer::u256_safe_div_rem(self, shift);
        let (rest, out31) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out30) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out29) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out28) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out27) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out26) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out25) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out24) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out23) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out22) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out21) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out20) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out19) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out18) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out17) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out16) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out15) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out14) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out13) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out12) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out11) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out10) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out9) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out8) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out7) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out6) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out5) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out4) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out3) = integer::u256_safe_div_rem(rest, shift);
        let (rest, out2) = integer::u256_safe_div_rem(rest, shift);
        let (_, out1) = integer::u256_safe_div_rem(rest, shift);
        let output = array![
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
        ];
        output.span()
    }
}

const POW_256_1: felt252 = 0x100;

#[generate_trait]
impl ByteArrayExt of ByteArrayExTrait {
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

fn u32s_to_u256(arr: Span<felt252>) -> u256 {
    assert!(arr.len() == 8, "u32s_to_u256: input must be 8 elements long");
    let high = *arr.at(0) * 0x1000000000000000000000000
        + *arr.at(1) * 0x10000000000000000
        + *arr.at(2) * 0x100000000
        + *arr.at(3);
    let high = high.try_into().expect('u32s_to_u256:overflow-high');
    let low = *arr.at(4) * 0x1000000000000000000000000
        + *arr.at(5) * 0x10000000000000000
        + *arr.at(6) * 0x100000000
        + *arr.at(7);
    let low = low.try_into().expect('u32s_to_u256:overflow-low');
    u256 { high, low }
}

fn u8s_to_u32s(input: Span<u8>) -> Array<u32> {
    let len = input.len();
    let mut output = array![];
    let mut i = 0;
    while i < len {
        let mut word = 0;
        let mut j = 0;
        while j != 4 {
            let byte = if i < len {
                (*input.at(i)).into()
            } else {
                0
            };
            word = word * 0x100 + byte;
            i += 1;
            j += 1;
        };
        output.append(word);
    };
    output
}
