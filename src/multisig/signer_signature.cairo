#[derive(Copy, Drop, Serde)]
struct SignerSignature {
    signer: felt252,
    signature_r: felt252,
    signature_s: felt252,
}

fn deserialize_array_signer_signature(
    mut serialized: Span<felt252>
) -> Option<Span<SignerSignature>> {
    let mut output = array![];
    loop {
        if serialized.len() == 0 {
            break Option::Some(output.span());
        }
        match Serde::deserialize(ref serialized) {
            Option::Some(signer_signature) => output.append(signer_signature),
            Option::None => { break Option::None; },
        };
    }
}
