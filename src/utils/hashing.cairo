use argent::offchain_message::interface::IStructHashRev1;
use argent::utils::bytes::{u8s_to_u32s_pad_end};
use argent::utils::serialization::{serialize};
use hash::HashStateTrait;
use poseidon::{hades_permutation, HashState};
use starknet::{class_hash_const, get_contract_address, library_call_syscall};

// Hashes two felts using poseidon
#[inline(always)]
fn poseidon_2(a: felt252, b: felt252) -> felt252 {
    let (hash, _, _) = hades_permutation(a, b, 2);
    hash
}

fn get_message_hash_rev_1_with_precalc<T, +Drop<T>, +IStructHashRev1<T>>(
    hades_permutation_state: (felt252, felt252, felt252), rev1_struct: T
) -> felt252 {
    // mainnet_domain_hash = domain.get_struct_hash_rev_1()
    // hades_permutation_state == hades_permutation('StarkNet Message', mainnet_domain_hash, 0);
    let (s0, s1, s2) = hades_permutation_state;

    let (fs0, fs1, fs2) = hades_permutation(
        s0 + get_contract_address().into(), s1 + rev1_struct.get_struct_hash_rev_1(), s2
    );
    HashState { s0: fs0, s1: fs1, s2: fs2, odd: false }.finalize()
}


fn sha256_cairo0(message: Span<u8>) -> Option<[u32; 8]> {
    let calldata = serialize(@(u8s_to_u32s_pad_end(message), message.len()));
    let class_hash = class_hash_const::<0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6d>();
    if let Result::Ok(output) = library_call_syscall(class_hash, selector!("sha256_cairo0"), calldata.span()) {
        if output.len() == 9 && *output.at(0) == 8 {
            let values: [u32; 8] = [
                (*output.at(1)).try_into().unwrap(),
                (*output.at(2)).try_into().unwrap(),
                (*output.at(3)).try_into().unwrap(),
                (*output.at(4)).try_into().unwrap(),
                (*output.at(5)).try_into().unwrap(),
                (*output.at(6)).try_into().unwrap(),
                (*output.at(7)).try_into().unwrap(),
                (*output.at(8)).try_into().unwrap(),
            ];
            return Option::Some(values);
        }
    }
    Option::None
}
