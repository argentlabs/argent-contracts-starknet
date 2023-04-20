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

fn deserialize_array_signer_signature(
    mut serialized: Span<felt252>
) -> Option<Span<SignerSignature>> {
    let mut output = ArrayTrait::new();
    loop {
        check_enough_gas();
        if serialized.len() == 0 {
            break Option::Some(output.span());
        }
        output.append(Serde::deserialize(ref serialized)?);
    }
}
