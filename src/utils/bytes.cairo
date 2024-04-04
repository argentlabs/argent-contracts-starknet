impl SpanU8TryIntoU256 of TryInto<Span<u8>, u256> {
    fn try_into(mut self: Span<u8>) -> Option<u256> {
        if self.len() < 32 {
            let result: felt252 = self.try_into()?;
            Option::Some(result.into())
        } else {
            let result: felt252 = self.slice(0, 31).try_into()?;
            let last_byte = *self.at(31);
            Option::Some((0x100 * result.into()) + last_byte.into())
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
    while let Option::Some(word1) = input
        .pop_front() {
            let word1 = *word1;
            let word2 = *input.pop_front().unwrap_or_default();
            let word3 = *input.pop_front().unwrap_or_default();
            let word4 = *input.pop_front().unwrap_or_default();
            output.append(0x100_00_00 * word1.into() + 0x100_00 * word2.into() + 0x100 * word3.into() + word4.into());
        };
    output
}
