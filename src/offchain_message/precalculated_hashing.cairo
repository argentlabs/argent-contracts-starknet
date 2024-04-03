use argent::offchain_message::interface::IStructHashRev1;
use hash::{HashStateTrait, HashStateExTrait};
use pedersen::PedersenTrait;
use poseidon::{poseidon_hash_span, hades_permutation, HashState};
use starknet::get_contract_address;

fn get_message_hash_rev_1_with_precalc<T, +Drop<T>, +Copy<T>, +IStructHashRev1<T>>(
    hades_permutation_sate: (felt252, felt252, felt252), rev1_struct: T
) -> felt252 {
    let (s0, s1, s2) = hades_permutation_sate;

    let (fs0, fs1, fs2) = hades_permutation(
        s0 + get_contract_address().into(), s1 + rev1_struct.get_struct_hash_rev_1(), s2
    );
    HashState { s0: fs0, s1: fs1, s2: fs2, odd: false }.finalize()
}
