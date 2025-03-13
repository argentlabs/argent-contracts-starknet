use argent::utils::bytes::{u8s_to_u32s_pad_end};
use argent::utils::serialization::{serialize};
use starknet::library_call_syscall;

// Hashes two felts using poseidon
#[inline(always)]
fn poseidon_2(a: felt252, b: felt252) -> felt252 {
    let (hash, _, _) = poseidon::hades_permutation(a, b, 2);
    hash
}


fn sha256_cairo0(message: Span<u8>) -> Option<Span<felt252>> {
    let calldata = serialize(@(u8s_to_u32s_pad_end(message), message.len()));
    let class_hash: starknet::ClassHash = 0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6d.try_into().unwrap();
    if let Result::Ok(output) = library_call_syscall(class_hash, selector!("sha256_cairo0"), calldata.span()) {
        if output.len() == 9 && *output.at(0) == 8 {
            return Option::Some(output.slice(1, 8));
        }
    }
    Option::None
}
