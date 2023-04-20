use array::ArrayTrait;
use serde::Serde;

use lib::check_enough_gas;

#[derive(Copy, Drop, Serde)]
struct SignerSignature {
    signer: felt252,
    signature_r: felt252,
    signature_s: felt252,
}

const SignerSignatureSize: usize = 3;

fn deserialize_array_signer_signature(
    serialized: Array<felt252>, mut current_output: Array<SignerSignature>, remaining: usize
) -> Option<Array<SignerSignature>> {
    check_enough_gas();

    if remaining == 0 {
        return Option::Some(current_output);
    }

    let mut span = Span { snapshot: @serialized };
    current_output.append(Serde::deserialize(ref span)?);

    deserialize_array_signer_signature(serialized, current_output, remaining - 1)
}

