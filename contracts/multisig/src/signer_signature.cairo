use array::ArrayTrait;
use serde::Serde;

use lib::check_enough_gas;

#[derive(Copy, Drop, Serde)]
struct SignerSignature {
    signer: felt252,
    signature_r: felt252,
    signature_s: felt252,
}

const SignerSignatureSize: usize = 3_usize;

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

