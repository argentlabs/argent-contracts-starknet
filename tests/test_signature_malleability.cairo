use argent::signer::signer_signature::{
    SECP_256_K1_HALF, SECP_256_R1_HALF, Secp256k1Signer, Secp256r1Signer, SignerSignature, SignerSignatureTrait,
};
use snforge_std::signature::{
    SignerTrait, secp256k1_curve::{Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl},
    secp256r1_curve::{Secp256r1CurveKeyPairImpl, Secp256r1CurveSignerImpl},
};
use starknet::eth_signature::public_key_point_to_eth_address;
use starknet::secp256_trait::{Secp256PointTrait, Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::Secp256r1Point;

#[test]
#[fuzzer(runs: 100)]
fn test_secp256r1_malleability(key: u256, message_hash: felt252) {
    let keypair = Secp256r1CurveKeyPairImpl::from_secret_key(key);
    let (r, s) = keypair.sign(message_hash.into()).unwrap();
    let signature = Signature { r, s: s % SECP_256_R1_HALF, y_parity: true };
    let recovered = recover_public_key::<Secp256r1Point>(message_hash.into(), signature).unwrap();
    let (pubkey, _) = recovered.get_coordinates().unwrap();
    let pubkey = pubkey.try_into().unwrap();
    let signer = Secp256r1Signer { pubkey };
    let signerSignature = SignerSignature::Secp256r1((signer, signature));
    assert!(signerSignature.is_valid_signature(message_hash));
}

#[test]
#[fuzzer(runs: 100)]
fn test_secp256k1_malleability(key: u256, message_hash: felt252) {
    let keypair = Secp256k1CurveKeyPairImpl::from_secret_key(key);
    let (r, s) = keypair.sign(message_hash.into()).unwrap();
    let signature = Signature { r, s: s % SECP_256_K1_HALF, y_parity: false };
    let public_key_point = recover_public_key::<Secp256k1Point>(message_hash.into(), signature).unwrap();
    let calculated_eth_address = public_key_point_to_eth_address::<Secp256k1Point>(:public_key_point);
    let signer = Secp256k1Signer { pubkey_hash: calculated_eth_address };
    let signerSignature = SignerSignature::Secp256k1((signer, signature));
    assert!(signerSignature.is_valid_signature(message_hash));
}

#[test]
#[should_panic(expected: ('argent/malleable-signature',))]
fn test_secp256r1_malleability_error() {
    let signature = Signature { r: 1, s: SECP_256_R1_HALF, y_parity: true };

    let signer = Secp256r1Signer { pubkey: 1 };
    let signerSignature = SignerSignature::Secp256r1((signer, signature));
    signerSignature.is_valid_signature(1);
}

#[test]
#[should_panic(expected: ('argent/malleable-signature',))]
fn test_secp256k1_malleability_error() {
    let signature = Signature { r: 1, s: SECP_256_K1_HALF + 1, y_parity: true };

    let signer = Secp256k1Signer { pubkey_hash: 1.try_into().unwrap() };
    let signerSignature = SignerSignature::Secp256k1((signer, signature));
    signerSignature.is_valid_signature(1);
}

