use argent::utils::bytes::{u8s_to_u32s_pad_end};
use argent::utils::serialization::{serialize};
use starknet::{class_hash_const, library_call_syscall};

// Hashes two felts using poseidon
#[inline(always)]
fn poseidon_2(a: felt252, b: felt252) -> felt252 {
    let (hash, _, _) = poseidon::hades_permutation(a, b, 2);
    hash
}

fn sha256_cairo0(mut message: Array<u8>) -> Option<Span<felt252>> {
    let init_len = message.len();
    // Append padding to make the length a multiple of 4
    let mut rest = 4 - (init_len % 4);
    while rest != 0 { // This could also be while message.len() % 4 != 0 but I believe it is more coslty, LMK
        message.append(0);
        rest -= 1;
    };
    let calldata = serialize(@(u8s_to_u32s_pad_end(message.span()), init_len));
    let class_hash = class_hash_const::<0x04dacc042b398d6f385a87e7dd65d2bcb3270bb71c4b34857b3c658c7f52cf6d>();
    if let Result::Ok(output) = library_call_syscall(class_hash, selector!("sha256_cairo0"), calldata.span()) {
        if output.len() == 9 && *output.at(0) == 8 {
            return Option::Some(output.slice(1, 8));
        }
    }
    Option::None
}
