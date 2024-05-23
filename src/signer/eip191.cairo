use argent::signer::signer_signature::{Eip191Signer, is_valid_secp256k1_signature};
use integer::{u128_byte_reverse, u256_safe_div_rem, u256_as_non_zero};
use keccak::cairo_keccak;
use starknet::secp256_trait::{Signature as Secp256Signature};
use starknet::{EthAddress, eth_signature::is_eth_signature_valid};

#[must_use]
#[inline(always)]
fn is_valid_eip191_signature(hash: felt252, signer: Eip191Signer, signature: Secp256Signature) -> bool {
    is_valid_secp256k1_signature(calculate_eip191_hash(hash), signer.eth_address.into(), signature)
}

#[must_use]
fn calculate_eip191_hash(message: felt252) -> u256 {
    // This functions allows to verify eip-191 signatures

    // split message into pieces
    let shift_4_bytes = u256_as_non_zero(0x100000000);
    let shift_8_bytes = u256_as_non_zero(0x10000000000000000);

    let rest: u256 = message.into();
    let (rest, tx_hash_part_5) = u256_safe_div_rem(rest, shift_4_bytes);
    let (rest, tx_hash_part_4) = u256_safe_div_rem(rest, shift_8_bytes);
    let (rest, tx_hash_part_3) = u256_safe_div_rem(rest, shift_8_bytes);
    let (tx_hash_part_1, tx_hash_part_2) = u256_safe_div_rem(rest, shift_8_bytes);

    let tx_hash_part_1: u64 = tx_hash_part_1.try_into().unwrap(); // 4 bytes 
    let tx_hash_part_2: u64 = tx_hash_part_2.try_into().unwrap(); // 8 bytes
    let tx_hash_part_3: u64 = tx_hash_part_3.try_into().unwrap(); // 8 bytes
    let tx_hash_part_4: u64 = tx_hash_part_4.try_into().unwrap(); // 8 bytes
    let tx_hash_part_5: u64 = tx_hash_part_5.try_into().unwrap(); // 4 bytes

    // The hardcoded values corresponds to the string `\x19Ethereum Signed Message:\n32`
    // or 0x19457468657265750x6d205369676e65640x204d6573736167650x3a0a3332
    // cairo_keccak inputs need to be little endian
    let mut hash_input: Array<u64> = array![
        0x7565726568744519, // = to_le(0x1945746865726575), 
        0x64656E676953206D, // = to_le(0x6d205369676e6564),
        0x6567617373654D20, // = to_le(0x204d657373616765), 
        to_le(0x3a0a333200000000 + tx_hash_part_1),
        to_le(tx_hash_part_2),
        to_le(tx_hash_part_3),
        to_le(tx_hash_part_4),
    ];
    // last part needs padded at the end with the missing 4 bytes
    let hash_input_last_word = to_le(tx_hash_part_5 * 0x100000000);

    let hash_result_le = cairo_keccak(ref hash_input, hash_input_last_word, 4);

    // convert result to big endian
    return u256 { low: u128_byte_reverse(hash_result_le.high), high: u128_byte_reverse(hash_result_le.low), };
}

// converts from big endian to little endian
#[must_use]
#[inline(always)]
fn to_le(input: u64) -> u64 {
    let result_u128 = u128_byte_reverse(input.into());
    let result_u128_shifted = result_u128 / 0x10000000000000000;
    result_u128_shifted.try_into().unwrap()
}
