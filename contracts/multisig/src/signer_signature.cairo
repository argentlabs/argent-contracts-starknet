use array::ArrayTrait;
use array::SpanTrait;
use serde::Serde;

use lib::check_enough_gas;

#[derive(Copy, Drop, Serde)]
struct SignerSignature {
    signer: felt252,
    signature_r: felt252,
    signature_s: felt252,
}

const SignerSignatureSize: usize = 3;

fn deserialize_array_signer_signature(serialized: Span<felt252>) -> Option<Span<SignerSignature>> {
    deserialize_array_signer_signature_helper(serialized, ArrayTrait::new())
}

fn deserialize_array_signer_signature_helper(
    mut serialized: Span<felt252>, mut curr_output: Array<SignerSignature>
) -> Option<Span<SignerSignature>> {
    check_enough_gas();

    if serialized.len() == 0 {
        Option::Some(curr_output.span())
    } else if serialized.len() < SignerSignatureSize {
        Option::None(())
    } else {
        curr_output.append(Serde::deserialize(ref serialized)?);
        deserialize_array_signer_signature_helper(serialized, curr_output)
    }
}
