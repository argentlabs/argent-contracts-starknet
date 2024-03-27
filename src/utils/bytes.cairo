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

const POW_256_1: felt252 = 0x100;

#[generate_trait]
impl ByteArrayExt of ByteArrayExTrait {
    fn is_empty(self: @ByteArray) -> bool {
        self.len() == 0
    }

    fn append_span_bytes(ref self: ByteArray, mut bytes: Span<u8>) {
        loop {
            match bytes.pop_front() {
                Option::Some(val) => self.append_byte(*val),
                Option::None => { break; }
            }
        }
    }

    fn from_bytes(mut bytes: Span<u8>) -> ByteArray {
        let mut arr: ByteArray = Default::default();
        let (nb_full_words, pending_word_len) = DivRem::div_rem(bytes.len(), 31_u32.try_into().unwrap());
        let mut i = 0;
        loop {
            if i == nb_full_words {
                break;
            };
            let mut word: felt252 = 0;
            let mut j = 0;
            loop {
                if j == 31 {
                    break;
                };
                word = word * POW_256_1 + (*bytes.pop_front().unwrap()).into();
                j += 1;
            };
            arr.data.append(word.try_into().unwrap());
            i += 1;
        };

        if pending_word_len == 0 {
            return arr;
        };

        let mut pending_word: felt252 = 0;
        let mut i = 0;

        loop {
            if i == pending_word_len {
                break;
            };
            pending_word = pending_word * POW_256_1.into() + (*bytes.pop_front().unwrap()).into();
            i += 1;
        };
        arr.pending_word_len = pending_word_len;
        arr.pending_word = pending_word;
        arr
    }

    fn into_bytes(self: ByteArray) -> Array<u8> {
        let len = self.len();
        let mut output: Array<u8> = Default::default();
        let mut i = 0;
        loop {
            if i == len {
                break;
            };
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

// last word zero padded to the right
fn u8s_to_u32s(input: Span<u8>) -> Array<u32> {
    let length = input.len();
    let mut output = array![];
    let mut i = 0;
    while i < length {
        let mut word = 0;
        let mut j = 0;
        while j != 4 {
            let byte = if i < length {
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
