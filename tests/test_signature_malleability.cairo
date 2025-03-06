use argent::signer::signer_signature::{
    SECP_256_K1_HALF, SECP_256_R1_HALF, Secp256k1Signer, Secp256r1Signer, SignerSignature, SignerSignatureTrait,
};
use snforge_std::signature::{
    SignerTrait, secp256k1_curve::{Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl},
    secp256r1_curve::{Secp256r1CurveKeyPairImpl, Secp256r1CurveSignerImpl},
};
use starknet::secp256_trait::{Secp256PointTrait, Signature as Secp256Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::Secp256r1Point;

#[test]
#[fuzzer(runs: 100)]
fn test_secp256r1_malleability(key: u128, message_hash: felt252) {
    let keypair = Secp256r1CurveKeyPairImpl::from_secret_key(key.into());
    let (r, s) = keypair.sign(message_hash.into()).unwrap();
    let sig = if s > SECP_256_R1_HALF {
        Secp256Signature { r, s: s - SECP_256_R1_HALF, y_parity: true }
    } else {
        Secp256Signature { r, s, y_parity: false }
    };
    let recovered = recover_public_key::<Secp256r1Point>(message_hash.into(), sig).expect('argent/invalid-sig-format');
    let (pubkey, _) = recovered.get_coordinates().expect('argent/invalid-sig-format');
    let pubkey = pubkey.try_into().unwrap();
    let sec = Secp256r1Signer { pubkey };
    let sig = SignerSignature::Secp256r1((sec, sig));
    sig.is_valid_signature(message_hash.into());
}

#[test]
#[fuzzer(runs: 100)]
fn test_secp256k1_malleability(key: u128, message_hash: felt252) {
    let keypair = Secp256k1CurveKeyPairImpl::from_secret_key(key.into());
    let (r, s) = keypair.sign(message_hash.into()).unwrap();
    let sig = if s > SECP_256_K1_HALF {
        Secp256Signature { r, s: s - SECP_256_K1_HALF, y_parity: true }
    } else {
        Secp256Signature { r, s, y_parity: false }
    };
    let recovered = recover_public_key::<Secp256k1Point>(message_hash.into(), sig).expect('argent/invalid-sig-format');
    let (pubkey, _) = recovered.get_coordinates().expect('argent/invalid-sig-format');
    let pubkey_hash = pubkey.try_into().unwrap();
    let sec = Secp256k1Signer { pubkey_hash };
    let sig = SignerSignature::Secp256k1((sec, sig));
    sig.is_valid_signature(message_hash.into());
}
// TODO Test with S too big to make sure it fails as expected?


