use argent::signer::eip191::calculate_eip191_hash;
use argent::signer::signer_signature::{
    Eip191Signer, SECP_256_K1_HALF, SECP_256_R1_HALF, STARK_CURVE_ORDER_U256, Secp256k1Signer, Secp256r1Signer,
    SignerSignature, SignerSignatureTrait,
};
use crate::{Eip191KeyPair, Secp256k1KeyPair, Secp256r1KeyPair, SignerKeyPairTestTrait, StarknetKeyPair};
use snforge_std::signature::secp256k1_curve::Secp256k1CurveSignerImpl;
use starknet::secp256_trait::{Secp256Trait, Signature};
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::Secp256r1Point;

// Starknet
#[test]
#[fuzzer(runs: 100)]
fn test_stark_curve(message_hash: felt252) {
    let signer = StarknetKeyPair::random();
    let signer_signature = signer.sign(message_hash);

    assert!(signer_signature.is_valid_signature(message_hash));

    let signature = signer.sign_concrete(message_hash);
    // Invalid with different s
    let mut modified_signature = signature;
    modified_signature.s = signature.s - 1;
    let signer_signature = SignerSignature::Starknet((signer.signer_concrete(), modified_signature));
    assert!(!signer_signature.is_valid_signature(message_hash));
}

#[test]
#[should_panic(expected: ('argent/invalid-r-value',))]
fn test_stark_curve_order_r() {
    let signer = StarknetKeyPair::random();
    let message_hash = 1;

    let mut modified_signature = signer.sign_concrete(message_hash);
    modified_signature.r = (STARK_CURVE_ORDER_U256 + 1).try_into().unwrap();
    let signer_signature = SignerSignature::Starknet((signer.signer_concrete(), modified_signature));
    signer_signature.is_valid_signature(message_hash);
}

#[test]
#[should_panic(expected: ('argent/invalid-s-value',))]
fn test_stark_curve_order_s() {
    let signer = StarknetKeyPair::random();
    let message_hash = 1;

    let mut modified_signature = signer.sign_concrete(message_hash);
    modified_signature.s = (STARK_CURVE_ORDER_U256 + 1).try_into().unwrap();
    let signer_signature = SignerSignature::Starknet((signer.signer_concrete(), modified_signature));
    signer_signature.is_valid_signature(message_hash);
}


// Secp256r1
#[test]
fn test_SECP_256_R1_HALF() {
    assert_eq!(SECP_256_R1_HALF, Secp256Trait::<Secp256r1Point>::get_curve_size() / 2);
}

#[test]
#[fuzzer(runs: 100)]
fn test_secp256r1(message_hash: felt252) {
    let signer = Secp256r1KeyPair::random();
    let signer_signature = signer.sign(message_hash);

    assert!(signer_signature.is_valid_signature(message_hash));

    let signature = signer.sign_concrete(message_hash);
    // Invalid with different s
    let mut modified_signature = signature;
    modified_signature.s = signature.s - 1;
    let signer_signature = SignerSignature::Secp256r1((signer.signer_concrete(), modified_signature));
    assert!(!signer_signature.is_valid_signature(message_hash));

    // Invalid with different r
    // This is 2 other tests

    // Invalid with different y_parity
    let mut modified_signature = signature;
    modified_signature.y_parity = !signature.y_parity;
    let signer_signature = SignerSignature::Secp256r1((signer.signer_concrete(), modified_signature));
    assert!(!signer_signature.is_valid_signature(message_hash));
}

#[test]
#[should_panic(expected: ('argent/invalid-sig-format',))]
fn test_secp256r1_modified_r_invalid_sig_format() {
    let signer = Secp256r1KeyPair::from_secret(1);
    let message_hash = 1;

    // Panic with invalid r
    let mut signature = signer.sign_concrete(message_hash);
    signature.r = signature.r - 1;
    let signer_signature = SignerSignature::Secp256r1((signer.signer_concrete(), signature));
    signer_signature.is_valid_signature(message_hash);
}

#[test]
fn test_secp256r1_modified_r() {
    let signer = Secp256r1KeyPair::from_secret(3);
    let message_hash = 1;
    let mut signature = signer.sign_concrete(message_hash);

    // Invalid with valid signature format but wrong r
    signature.r = signature.r - 1;
    let signer_signature = SignerSignature::Secp256r1((signer.signer_concrete(), signature));
    assert!(!signer_signature.is_valid_signature(message_hash));
}

#[test]
#[should_panic(expected: ('argent/malleable-signature',))]
fn test_secp256r1_malleability_error() {
    let signature = Signature { r: 1, s: SECP_256_R1_HALF + 1, y_parity: true };

    let signer = Secp256r1Signer { pubkey: 1 };
    let signerSignature = SignerSignature::Secp256r1((signer, signature));
    signerSignature.is_valid_signature(1);
}

#[test]
#[should_panic(expected: ('argent/invalid-r-value',))]
fn test_secp256r1_high_r() {
    let r = Secp256Trait::<Secp256r1Point>::get_curve_size();
    let signature = Signature { r, s: 1, y_parity: true };

    let signer = Secp256r1Signer { pubkey: 1 };
    let signerSignature = SignerSignature::Secp256r1((signer, signature));
    signerSignature.is_valid_signature(1);
}

#[test]
#[should_panic(expected: ('argent/invalid-r-value',))]
fn test_secp256r1_0_r() {
    let signature = Signature { r: 0, s: 1, y_parity: true };

    let signer = Secp256r1Signer { pubkey: 1 };
    let signerSignature = SignerSignature::Secp256r1((signer, signature));
    signerSignature.is_valid_signature(1);
}

#[test]
#[should_panic(expected: ('argent/invalid-s-value',))]
fn test_secp256r1_high_s() {
    let s = Secp256Trait::<Secp256r1Point>::get_curve_size();
    let signature = Signature { r: 1, s, y_parity: true };

    let signer = Secp256r1Signer { pubkey: 1 };
    let signerSignature = SignerSignature::Secp256r1((signer, signature));
    signerSignature.is_valid_signature(1);
}

#[test]
#[should_panic(expected: ('argent/invalid-s-value',))]
fn test_secp256r1_0_s() {
    let signature = Signature { r: 1, s: 0, y_parity: true };

    let signer = Secp256r1Signer { pubkey: 1 };
    let signerSignature = SignerSignature::Secp256r1((signer, signature));
    signerSignature.is_valid_signature(1);
}

// Secp256k1
#[test]
fn test_SECP_256_K1_HALF() {
    assert_eq!(SECP_256_K1_HALF, Secp256Trait::<Secp256k1Point>::get_curve_size() / 2);
}

#[test]
#[fuzzer(runs: 100)]
fn test_secp256k1(message_hash: felt252) {
    let signer = Secp256k1KeyPair::random();
    let signer_signature = signer.sign(message_hash);
    assert!(signer_signature.is_valid_signature(message_hash));

    let signature = signer.sign_concrete(message_hash);
    // Invalid with different s
    let mut modified_signature = signature;
    modified_signature.s = signature.s - 1;
    let signer_signature = SignerSignature::Secp256k1((signer.signer_concrete(), modified_signature));
    assert!(!signer_signature.is_valid_signature(message_hash));

    // Invalid with different r
    // This is 2 other tests

    // Invalid with different y_parity
    let mut modified_signature = signature;
    modified_signature.y_parity = !signature.y_parity;
    let signer_signature = SignerSignature::Secp256k1((signer.signer_concrete(), modified_signature));
    assert!(!signer_signature.is_valid_signature(message_hash));
}

#[test]
#[should_panic(expected: ('Option::unwrap failed.',))]
fn test_secp256k1_modified_r_invalid_sig_format() {
    let signer = Secp256k1KeyPair::from_secret(1);
    let message_hash = 1;

    let mut signature = signer.sign_concrete(message_hash);
    // Panic with invalid r
    signature.r = signature.r - 1;
    let signer_signature = SignerSignature::Secp256k1((signer.signer_concrete(), signature));
    signer_signature.is_valid_signature(message_hash);
}

#[test]
fn test_secp256k1_modified_r() {
    let signer = Secp256k1KeyPair::from_secret(3);
    let message_hash = 1;

    let mut signature = signer.sign_concrete(message_hash);
    // Invalid with valid signature format but wrong r
    signature.r = signature.r - 1;
    let signer_signature = SignerSignature::Secp256k1((signer.signer_concrete(), signature));
    assert!(!signer_signature.is_valid_signature(message_hash));
}

#[test]
#[should_panic(expected: ('argent/malleable-signature',))]
fn test_secp256k1_malleability_error() {
    let signature = Signature { r: 1, s: SECP_256_K1_HALF + 1, y_parity: true };

    let signer = Secp256k1Signer { pubkey_hash: 1.try_into().unwrap() };
    let signerSignature = SignerSignature::Secp256k1((signer, signature));
    signerSignature.is_valid_signature(1);
}

// Eip191
#[test]
fn test_eip191_hashing() {
    const TX_HASH: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;
    let hash_result = calculate_eip191_hash(TX_HASH);
    assert_eq!(hash_result, 48405440187118761992760719389369972157723609501777497852552048540887957431744);
}

#[test]
#[fuzzer(runs: 100)]
fn test_eip191_verification(message_hash: felt252) {
    let signer = Eip191KeyPair::random();
    let signer_signature = signer.sign(message_hash);
    assert!(signer_signature.is_valid_signature(message_hash));

    let signature = signer.sign_concrete(message_hash);
    // Invalid with different s
    let mut modified_signature = signature;
    modified_signature.s = signature.s - 1;
    let signer_signature = SignerSignature::Eip191((signer.signer_concrete(), modified_signature));
    assert!(!signer_signature.is_valid_signature(message_hash));

    // Invalid with different r
    // This is 2 other tests

    // Invalid with different y_parity
    let mut modified_signature = signature;
    modified_signature.y_parity = !signature.y_parity;
    let signer_signature = SignerSignature::Eip191((signer.signer_concrete(), modified_signature));
    assert!(!signer_signature.is_valid_signature(message_hash));
}


#[test]
#[should_panic(expected: ('Option::unwrap failed.',))]
fn test_eip191_modified_r_invalid_sig_format() {
    let signer = Eip191KeyPair::from_secret(1);
    let message_hash = 1;

    let mut signature = signer.sign_concrete(message_hash);
    // Panic with invalid r
    signature.r = signature.r - 1;
    let signer_signature = SignerSignature::Eip191((signer.signer_concrete(), signature));
    signer_signature.is_valid_signature(message_hash);
}

#[test]
fn test_eip191_modified_r() {
    let signer = Eip191KeyPair::from_secret(4);
    let message_hash = 1;

    let mut signature = signer.sign_concrete(message_hash);
    // Invalid with valid signature format but wrong r
    signature.r = signature.r - 1;
    let signer_signature = SignerSignature::Eip191((signer.signer_concrete(), signature));
    assert!(!signer_signature.is_valid_signature(message_hash));
}


#[test]
#[should_panic(expected: ('argent/malleable-signature',))]
fn test_eip191_malleability_error() {
    let signature = Signature { r: 1, s: SECP_256_K1_HALF + 1, y_parity: true };

    let signer = Eip191Signer { eth_address: 1.try_into().unwrap() };
    let signerSignature = SignerSignature::Eip191((signer, signature));
    signerSignature.is_valid_signature(1);
}
