use argent::common::signer_signature::{SignerSignature, StarknetSignature};
use core::debug::PrintTrait;
use integer::{u32_safe_divmod, u32_to_felt252};

fn to_starknet_signer_signatures(arr: Array<felt252>) -> Array<felt252> {
    let size = arr.len() / 3_u32;
    let mut signatures = array![u32_to_felt252(size)];
    let mut i: usize = 0;
    loop {
        if i == size {
            break;
        }
        let signer_signature = SignerSignature::Starknet(
            (*arr.at(i * 3), StarknetSignature { r: *arr.at(i * 3 + 1), s: *arr.at(i * 3 + 2) })
        );
        signer_signature.serialize(ref signatures);
        i += 1;
    };
    signatures
}
