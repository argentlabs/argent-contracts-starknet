use core::poseidon::hades_permutation;

// Hashes two felts using poseidon
pub fn poseidon_2(a: felt252, b: felt252) -> felt252 {
    let (hash, _, _) = hades_permutation(a, b, 2);
    hash
}
