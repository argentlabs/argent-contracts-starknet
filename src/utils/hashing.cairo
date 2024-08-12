use argent::utils::bytes::{u8s_to_u32s_pad_end};
use argent::utils::serialization::{serialize};
use starknet::{class_hash_const, library_call_syscall};

// Hashes two felts using poseidon
#[inline(always)]
fn poseidon_2(a: felt252, b: felt252) -> felt252 {
    let (hash, _, _) = poseidon::hades_permutation(a, b, 2);
    hash
}
