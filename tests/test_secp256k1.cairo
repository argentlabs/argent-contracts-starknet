use argent::signer::signer_signature::{
    SignerSignature, SignerSignatureTrait, Secp256k1Signer, Secp256Signature, SECP_256_K1_HALF
};
use starknet::secp256_trait::{Secp256PointTrait, Secp256Trait};
use starknet::secp256k1::Secp256k1Point;

const pubkey_hash: felt252 = 0x8eD43fe3d24dA31f142688E6469D8E76B0a5a2f3;

const message_hash_low_even: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000000;
const sig_r_low_even: u256 = 0xab8632d5292334de6975701e879636ffa35fd85bc41e76e45846e47f527d456;
const sig_s_low_even: u256 = 0x4cf9f03153c75801f44df099b834136dfe0c24d07946d7ef1b5f2a9f7fc96a6b;

const message_hash_low_odd: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000003;
const sig_r_low_odd: u256 = 0x2398098474010b6412d14ff7f0e71333f111c86497a821b4280b40290c655b54;
const sig_s_low_odd: u256 = 0x610bc68cff84fb88afca48afcc4e00aac0aad029d2d039ce196bf810fc06da0;

const message_hash_high_even: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000001;
const sig_r_high_even: u256 = 0x67cc6f41089710610ceb2bb3b19ea2551fde3836ad6b41a196e8c321f1c5a6f1;
const sig_s_high_even: u256 = 0x6a5eb05e5f33549368633dcb426fadf8ac28e4357b366ec1ef4f4abdbf115cec;

const message_hash_high_odd: felt252 = 0x100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000002;
const sig_r_high_odd: u256 = 0xb3ae64ca4f2ed20646eac3d6801b208bfbb50c04aea3947e17d518f74f789ff;
const sig_s_high_odd: u256 = 0x33486eb4073a267b3949411bd76ee83d6c9b1135956e8f5089e190811e9cd9fa;

fn validateK1Signature(r: u256, s: u256, y_parity: bool, message_hash: felt252) -> bool {
    let sig = SignerSignature::Secp256k1(
        (Secp256k1Signer { pubkey_hash: pubkey_hash.try_into().unwrap() }, Secp256Signature { r, s, y_parity })
    );
    sig.is_valid_signature(message_hash)
}


#[test]
fn test_SECP_256_K1_HALF() {
    assert!(SECP_256_K1_HALF == Secp256Trait::<Secp256k1Point>::get_curve_size() / 2,);
}

#[test]
fn test_successful_verification_low_even() {
    assert!(
        validateK1Signature(sig_r_low_even, sig_s_low_even, true, message_hash_low_even),
        "invalid-verification-low-even"
    );
}

#[test]
fn test_successful_verification_low_odd() {
    assert!(
        validateK1Signature(sig_r_low_odd, sig_s_low_odd, false, message_hash_low_odd), "invalid-verification-low-odd"
    );
}

#[test]
fn test_successful_verification_high_even() {
    assert!(
        validateK1Signature(sig_r_high_even, sig_s_high_even, true, message_hash_high_even),
        "invalid-verification-high-even"
    );
}

#[test]
fn test_successful_verification_high_odd() {
    assert!(
        validateK1Signature(sig_r_high_odd, sig_s_high_odd, false, message_hash_high_odd),
        "invalid-verification-high-odd"
    );
}
