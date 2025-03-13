use argent::signer::signer_signature::{
    SECP_256_K1_HALF, SECP_256_R1_HALF, Secp256k1Signer, Secp256r1Signer, SignerSignature, SignerSignatureTrait,
};
use snforge_std::signature::{
    KeyPair, SignerTrait, secp256k1_curve::{Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl},
    secp256r1_curve::{Secp256r1CurveKeyPairImpl, Secp256r1CurveSignerImpl},
};
use starknet::eth_signature::public_key_point_to_eth_address;
use starknet::secp256_trait::Secp256Trait;
use starknet::secp256_trait::{Secp256PointTrait, Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;

#[test]
#[fuzzer(runs: 100)]
fn test_secp256r1_malleability(message_hash: felt252) {
    let keypair = Secp256r1CurveKeyPairImpl::generate();
    let signer = Secp256r1Signer { pubkey: keypair.get_pubkey().try_into().unwrap() };
    let signature = keypair.sign_with_parity(message_hash.into());
    assert!(SignerSignature::Secp256r1((signer, signature)).is_valid_signature(message_hash));
}

#[test]
#[fuzzer(runs: 100)]
fn test_secp256k1_malleability(message_hash: felt252, y_parity_random: u8) {
    let keypair = Secp256k1CurveKeyPairImpl::generate();
    let calculated_eth_address = public_key_point_to_eth_address::<Secp256k1Point>(keypair.public_key);
    let signer = Secp256k1Signer { pubkey_hash: calculated_eth_address };
    let signature = keypair.sign_with_parity(message_hash.into());
    assert!(SignerSignature::Secp256k1((signer, signature)).is_valid_signature(message_hash));
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
#[should_panic(expected: ('argent/malleable-signature',))]
fn test_secp256k1_malleability_error() {
    let signature = Signature { r: 1, s: SECP_256_K1_HALF + 1, y_parity: true };

    let signer = Secp256k1Signer { pubkey_hash: 1.try_into().unwrap() };
    let signerSignature = SignerSignature::Secp256k1((signer, signature));
    signerSignature.is_valid_signature(1);
}

#[generate_trait]
pub impl Secp256SignerImpl<
    T, +SignerTrait<KeyPair<u256, T>, u256, (u256, u256)>, +Secp256PointTrait<T>, +Secp256Trait<T>, +Drop<T>, +Copy<T>,
> of Secp256Signer<T> {
    fn sign_with_parity(self: KeyPair<u256, T>, message_hash: u256) -> Signature {
        let (r, s) = self.sign(message_hash).unwrap();
        let (pubkey_y_true, _) = recover_public_key::<T>(message_hash, Signature { r, s, y_parity: true })
            .unwrap()
            .get_coordinates()
            .unwrap();
        let raw_signature = Signature { r, s, y_parity: pubkey_y_true == self.get_pubkey() };
        // Normalize the signature
        let curve_size = Secp256Trait::<T>::get_curve_size();
        if raw_signature.s > curve_size / 2 {
            Signature { r: raw_signature.r, s: curve_size - raw_signature.s, y_parity: !raw_signature.y_parity }
        } else {
            raw_signature
        }
    }

    fn get_pubkey(self: KeyPair<u256, T>) -> u256 {
        let (pubkey, _) = self.public_key.get_coordinates().unwrap();
        pubkey
    }
}
