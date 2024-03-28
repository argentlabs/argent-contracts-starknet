fn extend(ref arr: Array<u8>, mut src: Span<u8>) {
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
        while let Option::Some(byte) = self
            .pop_front() {
                let byte: u256 = (*byte).into();
                result = (256 * result) + byte; // x << 8 is the same as x * 256
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
        loop {
            match self.pop_front() {
                Option::Some(byte) => {
                    let byte: felt252 = (*byte).into();
                    result = (256 * result) + byte; // x << 8 is the same as x * 256
                },
                Option::None => { break Option::Some(result); }
            };
        }
    }
}

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

fn u32s_to_u8s(mut input: Span<felt252>) -> Span<u8> {
    let mut output = array![];
    while let Option::Some(word) = input.pop_front() {
        let word: u32 = (*word).try_into().unwrap();
        output.append(((word / 0x1000000) & 0xFF).try_into().unwrap());
        output.append(((word / 0x10000) & 0xFF).try_into().unwrap());
        output.append(((word / 0x100) & 0xFF).try_into().unwrap());
        output.append((word & 0xFF).try_into().unwrap());
    };
    output.span()
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
