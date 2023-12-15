fn extend(ref arr: Array<u8>, src: @Array<u8>) {
    let mut src = src.span();
    loop {
        match src.pop_front() {
            Option::Some(a) => arr.append(*a),
            Option::None => { break; },
        };
    };
}

impl SpanU8TryIntoU256 of TryInto<Span<u8>, u256> {
    fn try_into(mut self: Span<u8>) -> Option<u256> {
        if self.len() > 32 {
            return Option::None;
        }
        let mut result = 0;
        loop {
            match self.pop_front() {
                Option::Some(byte) => {
                    let byte: u256 = (*byte).into();
                    result = (256 * result) + byte; // x << 8 is the same as x * 256
                },
                Option::None => { break Option::Some(result); }
            };
        }
    }
}

impl SpanU8TryIntoFelt252 of TryInto<Span<u8>, felt252> {
    fn try_into(mut self: Span<u8>) -> Option<felt252> {
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
