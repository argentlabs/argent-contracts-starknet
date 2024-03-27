use argent::utils::bytes::{u8s_to_u32s, u32s_to_u256};
use argent::utils::serialization::{serialize};
use starknet::{class_hash_const, library_call_syscall};

// Hashes two felts using poseidon
#[inline(always)]
fn poseidon_2(a: felt252, b: felt252) -> felt252 {
    let (hash, _, _) = poseidon::hades_permutation(a, b, 2);
    hash
}

fn sha256_cairo0(message: Span<u8>) -> Span<felt252> {
    let mut calldata = serialize(@u8s_to_u32s(message));
    calldata.append(message.len().into());
    let class_hash = class_hash_const::<0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6d>();
    match library_call_syscall(class_hash, selector!("sha256_cairo0"), calldata.span()) {
        Result::Ok(output) => {
            assert!(output.len() == 9 && *output.at(0) == 8, "invalid-output-format");
            output.slice(1, 8)
        },
        Result::Err(err) => panic(err),
    }
}
