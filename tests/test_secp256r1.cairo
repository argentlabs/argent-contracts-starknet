use argent::signer::signer_signature::{
    SignerSignature, SignerSignatureTrait, Secp256r1Signer, Secp256Signature, SECP_256_R1_HALF
};
use starknet::secp256_trait::{Secp256PointTrait, Secp256Trait};
use starknet::secp256r1::Secp256r1Point;

const pubkey: u256 = 0xbde58cc7c321604ffec0de496616a6eb88481f6438900dec19167a4322d93ec0;

const message_hash_low_even: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403000000a;
const sig_r_low_even: u256 = 0x7b2db604cc84573075d9c05c17b554698fd58b533b36f6ff1caddf0fbb736444;
const sig_s_low_even: u256 = 0x3d682fa0fe6acc66881b9bee6c3764c9dcf7c63953da5c40df6cf7a73dfb2d68;

const message_hash_low_odd: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000002;
const sig_r_low_odd: u256 = 0x97f999dbe4744facf223aa668cedeb0db43349941e0ddc7329ea2f44a3abf963;
const sig_s_low_odd: u256 = 0xcf565cf05762c8096fbe373c844cae1923157bf4f17fa034fa22935f1903fb;

const message_hash_high_even: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000001;
const sig_r_high_even: u256 = 0x145b7eef58bc8eba4cca59d0f0fef3f1889031ce077b26d9b791e6d80d234ad7;
const sig_s_high_even: u256 = 0x7ebcd91ea1ad647ecc99b67135f7f136c198eeb13f690c5be91d8142a18a1509;

const message_hash_high_odd: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000005;
const sig_r_high_odd: u256 = 0x787293332b1d654aaf0d01ffb7969079f317cd60e968e11a485149e2ca0bf981;
const sig_s_high_odd: u256 = 0x56dfd723ec56c6f85cdaa82be0125a2c2e2bb602a4c61a46e3340db7b2ab76c;


fn validateR1Signature(r: u256, s: u256, y_parity: bool, message_hash: felt252) -> bool {
    let sig = SignerSignature::Secp256r1(
        (Secp256r1Signer { pubkey: pubkey.try_into().unwrap() }, Secp256Signature { r, s, y_parity })
    );
    sig.is_valid_signature(message_hash)
}

#[test]
fn test_SECP_256_R1_HALF() {
    assert!(SECP_256_R1_HALF == Secp256Trait::<Secp256r1Point>::get_curve_size() / 2,);
}

#[test]
fn test_successful_verification_low_even() {
    assert!(
        validateR1Signature(sig_r_low_even, sig_s_low_even, true, message_hash_low_even),
        "invalid-verification-low-even"
    );
}

#[test]
fn test_successful_verification_low_odd() {
    assert!(
        validateR1Signature(sig_r_low_odd, sig_s_low_odd, false, message_hash_low_odd), "invalid-verification-low-odd"
    );
}

#[test]
fn test_successful_verification_high_even() {
    assert!(
        validateR1Signature(sig_r_high_even, sig_s_high_even, true, message_hash_high_even),
        "invalid-verification-high-even"
    );
}

#[test]
fn test_successful_verification_high_odd() {
    assert!(
        validateR1Signature(sig_r_high_odd, sig_s_high_odd, false, message_hash_high_odd),
        "invalid-verification-high-odd"
    );
}

#[test]
#[should_panic(expected: ('argent/invalid-r-value',))]
fn test_high_r() {
    validateR1Signature(
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, sig_s_low_even, true, message_hash_low_even
    );
}

#[test]
#[should_panic(expected: ('argent/invalid-r-value',))]
fn test_0_r() {
    validateR1Signature(0, sig_s_low_even, true, message_hash_low_even);
}

#[test]
#[should_panic(expected: ('argent/invalid-s-value',))]
fn test_high_s() {
    validateR1Signature(
        sig_r_low_even, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, true, message_hash_low_even
    );
}

#[test]
#[should_panic(expected: ('argent/invalid-s-value',))]
fn test_0_s() {
    validateR1Signature(sig_r_low_even, 0, true, message_hash_low_even);
}

