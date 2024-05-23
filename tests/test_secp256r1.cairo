use argent::signer::signer_signature::{
    SignerSignature, SignerSignatureTrait, Secp256r1Signer, Secp256Signature, SECP_256_R1_HALF
};
use starknet::secp256_trait::{Secp256PointTrait, Secp256Trait};
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::Secp256r1Point;

const pubkey: u256 = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;

const message_hash_low_even: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403000000a;
const sig_r_low_even: u256 = 0xe5cf7bb34c524a31cba96652d5f7ed6fe10aff551b001a27120fa33f2d388003;
const sig_s_low_even: u256 = 0x25a09d693f9144bc3de17cc52aa55cbc1f3a45a4541d51c76a534a84c907d5d8;

const message_hash_low_odd: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403000000f;
const sig_r_low_odd: u256 = 0x30a2cc1195f766d2de35b106d70b78d5b99477c326f070b1abe9095dd0ca4c7f;
const sig_s_low_odd: u256 = 0x7069099721bc75387ae078a636f6b553a915dff0ea6002d3e1aed697ef08b543;

const message_hash_high_even: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000000;
const sig_r_high_even: u256 = 0xe87de4fb5143e7c360239db80c4b02bf340669435aec38038d97f47624dcbac2;
const sig_s_high_even: u256 = 0x6abeb3a0ca4f584bcf43b533b97c8c64c3a779eb869b43897558d85d7d57a56b;

const message_hash_high_odd: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000001;
const sig_r_high_odd: u256 = 0xd3a644568d134d2d7651b278dd60b85e3a5b59b5d1d0177c23d73ac6e8177a6d;
const sig_s_high_odd: u256 = 0x35fcf10f3d37fe1b3842e24fe8199f7b592cbe16203ae590d8d5ca78d4335efd;


fn validateR1Signature(r: u256, s: u256, y_parity: bool, message_hash: felt252) -> bool {
    let sig = SignerSignature::Secp256r1(
        (Secp256r1Signer { pubkey: pubkey.try_into().unwrap() }, Secp256Signature { r, s, y_parity })
    );
    sig.is_valid_signature(message_hash)
}

// (Secp256Trait::<Secp256r1Point>::get_curve_size() - sig_s

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

