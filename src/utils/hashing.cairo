use argent::utils::bytes::{u32s_to_u256};
use starknet::{class_hash_const, library_call_syscall};

// Hashes two felts using poseidon
#[inline(always)]
fn poseidon_2(a: felt252, b: felt252) -> felt252 {
    let (hash, _, _) = poseidon::hades_permutation(a, b, 2);
    hash
}
// fn sha256_cairo0(message: Span<u8>) -> Span<felt252> {
//     // let message = array!['loca', 'lhos', 't\x00\x00\x00'];
//     let mut calldata = array![];
//     message.serialize(ref calldata);
//     calldata.append(9);
//     let class_hash = class_hash_const::<0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6d>();
//     let res = library_call_syscall(class_hash, selector!("sha256_cairo0"), calldata.span()).unwrap();
//     assert!(res.len() == 9, "invalid-res-length");
//     let message_hash = u32s_to_u256(res.slice(1, 8));
//     println!("hash2: {}", message_hash);
//     assert!(message_hash == expected, "invalid-message-hash2");
// }


