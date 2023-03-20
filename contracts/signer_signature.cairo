use array::ArrayTrait;
use serde::Serde;

use contracts::check_enough_gas;


#[derive(Copy, Drop)]
struct SignerSignature {
    signer: felt252,
    signature_r: felt252,
    signature_s: felt252,
}

const SignerSignatureSize: usize = 3_usize;

impl SignerSignatureSerde of serde::Serde::<SignerSignature> {
    fn serialize(ref serialized: Array<felt252>, input: SignerSignature) {
        Serde::serialize(ref serialized, input.signer);
        Serde::serialize(ref serialized, input.signature_r);
        Serde::serialize(ref serialized, input.signature_s);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<SignerSignature> {
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
    serialized: Array<felt252>, mut curr_output: Array<SignerSignature>, remaining: usize
) -> Option<Array<SignerSignature>> {
    check_enough_gas();

    if remaining == 0_usize {
        return Option::Some(curr_output);
    }

    let mut span = Span { snapshot: @serialized };
    curr_output.append(Serde::deserialize(ref span)?);

    deserialize_array_signer_signature(serialized, curr_output, remaining - 1_usize)
}

