use array::ArrayTrait;
use serde::Serde;
use gas::get_gas;


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
    fn serialize(ref serialized: Array<felt>, input: SignerSignature) {
        Serde::serialize(ref serialized, input.signer);
        Serde::serialize(ref serialized, input.signature_r);
        Serde::serialize(ref serialized, input.signature_s);
    }
    fn deserialize(ref serialized: Span<felt>) -> Option<SignerSignature> {
        Option::Some(
            SignerSignature {
                signer: Serde::deserialize(ref serialized)?,
                signature_r: Serde::deserialize(ref serialized)?,
                signature_s: Serde::deserialize(ref serialized)?,
            }
        )
    }
}

fn deserialize_array_signer_signature(
    serialized: Array<felt>, mut curr_output: Array<SignerSignature>, remaining: usize
) -> Option<Array<SignerSignature>> {
    match get_gas() {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut data = ArrayTrait::new();
            data.append('Out of gas');
            panic(data);
        },
    }
    if remaining == 0_usize {
        return Option::Some(curr_output);
    }

    let mut span = Span { snapshot: @serialized };
    curr_output.append(Serde::deserialize(ref span)?);

    deserialize_array_signer_signature(serialized, curr_output, remaining - 1_usize)
}

