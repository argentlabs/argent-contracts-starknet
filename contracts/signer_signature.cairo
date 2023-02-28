use array::ArrayTrait;
use serde::Serde;

#[derive(Copy, Drop)]
struct SignerSignature {
    signer: felt,
    signature_r: felt,
    signature_s: felt,
}

const SignerSignatureSize: u32 = 3_u32;
impl SignerSignatureArrayCopy of Copy::<Array::<SignerSignature>>;
impl SignerSignatureArrayDrop of Drop::<Array::<SignerSignature>>;

impl SignerSignatureSerde of serde::Serde::<SignerSignature> {
    fn serialize(ref serialized: Array::<felt>, input: SignerSignature) {
        Serde::<felt>::serialize(ref serialized, input.signer);
        Serde::<felt>::serialize(ref serialized, input.signature_r);
        Serde::<felt>::serialize(ref serialized, input.signature_s);
    }
    fn deserialize(ref serialized: Array::<felt>) -> Option::<SignerSignature> {
        Option::Some(
            SignerSignature {
                signer: Serde::<felt>::deserialize(ref serialized)?,
                signature_r: Serde::<felt>::deserialize(ref serialized)?,
                signature_s: Serde::<felt>::deserialize(ref serialized)?,
            }
        )
    }
}

fn deserialize_array_signer_signature(
    ref serialized: Array::<felt>, mut curr_output: Array::<SignerSignature>, remaining: usize
) -> Option::<Array::<SignerSignature>> {
    match try_fetch_gas() {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut data = ArrayTrait::new();
            data.append('Out of gas');
            panic(data);
        },
    }
    if remaining == 0_usize {
        return Option::<Array::<SignerSignature>>::Some(curr_output);
    }
    curr_output.append(Serde::<SignerSignature>::deserialize(ref serialized)?);
    deserialize_array_signer_signature(ref serialized, curr_output, remaining - 1_usize)
}

