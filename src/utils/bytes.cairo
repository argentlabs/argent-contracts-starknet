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
        if self.len() > 32 {
            return Option::None;
        }
        let mut result = 0;
        while let Option::Some(byte) = self.pop_front() {
            let byte = (*byte).into();
            result = (0x100 * result) + byte;
        };
        Option::Some(result)
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

fn u32s_to_u256(arr: Span<felt252>) -> u256 {
    assert!(arr.len() == 8, "u32s_to_u256: input must be 8 elements long");
    let high = *arr.at(0) * 0x1000000000000000000000000
        + *arr.at(1) * 0x10000000000000000
        + *arr.at(2) * 0x100000000
        + *arr.at(3);
    let high = high.try_into().expect('u32s_to_u256:overflow-high');
    let low = *arr.at(4) * 0x1000000000000000000000000
        + *arr.at(5) * 0x10000000000000000
        + *arr.at(6) * 0x100_000_000
        + *arr.at(7);
    let low = low.try_into().expect('u32s_to_u256:overflow-low');
    u256 { high, low }
}

fn u32s_to_u8s(mut input: Span<felt252>) -> Span<u8> {
    let mut output = array![];
    while let Option::Some(word) = input
        .pop_front() {
            let word: u32 = (*word).try_into().unwrap();
            output.append(((word / 0x1000000) & 0xFF).try_into().unwrap());
            output.append(((word / 0x10000) & 0xFF).try_into().unwrap());
            output.append(((word / 0x100) & 0xFF).try_into().unwrap());
            output.append((word & 0xFF).try_into().unwrap());
        };
    output.span()
}

fn u8s_to_u32s(mut input: Span<u8>) -> Array<u32> {
    let mut output = array![];
    loop {
        let word1 = match input.pop_front() {
            Option::Some(word) => *word,
            Option::None => { break; }
        };
        let word2 = *input.pop_front().unwrap_or_default();
        let word3 = *input.pop_front().unwrap_or_default();
        let word4 = *input.pop_front().unwrap_or_default();
        output.append(0x1000000 * word1.into() + 0x10000 * word2.into() + 0x100 * word3.into() + word4.into());
    };
    output
}
