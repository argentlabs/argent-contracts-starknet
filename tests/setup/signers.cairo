use argent::signer::eip191::calculate_eip191_hash;
use argent::signer::signer_signature::{
    Eip191Signer, Secp256k1Signer, Secp256r1Signer, Signer, SignerSignature, SignerTrait, StarknetSignature,
    StarknetSigner,
};
use snforge_std::signature::{secp256k1_curve::{Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl}};
use snforge_std::{
    signature::{
        KeyPair, KeyPairTrait, SignerTrait as SnForgeSignerTrait,
        secp256r1_curve::{Secp256r1CurveKeyPairImpl, Secp256r1CurveSignerImpl},
        stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl},
    },
};
use starknet::eth_signature::public_key_point_to_eth_address;
use starknet::secp256_trait::Secp256Trait;
use starknet::secp256_trait::{Secp256PointTrait, Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::Secp256r1Point;

#[derive(Drop, Copy)]
struct StarknetSignerKeyPair {
    key_pair: KeyPair<felt252, felt252>,
}

#[derive(Drop, Copy)]
struct Secp256k1SignerKeyPair {
    key_pair: KeyPair<u256, Secp256k1Point>,
}

#[derive(Drop, Copy)]
struct Secp256r1SignerKeyPair {
    key_pair: KeyPair<u256, Secp256r1Point>,
}

#[derive(Drop, Copy)]
struct Eip191SignerKeyPair {
    key_pair: Secp256k1SignerKeyPair,
}

#[derive(Drop, Copy)]
pub enum SignerKeyPair {
    Starknet: StarknetSignerKeyPair,
    Secp256k1: Secp256k1SignerKeyPair,
    Secp256r1: Secp256r1SignerKeyPair,
    Eip191: Eip191SignerKeyPair,
    // Webauthn
}

#[generate_trait]
pub impl SignerKeyPairImpl of SignerKeyPairTrait {
    fn signer(self: @SignerKeyPair) -> Signer {
        match self {
            SignerKeyPair::Starknet(signer) => signer.signer(),
            SignerKeyPair::Secp256r1(signer) => signer.signer(),
            SignerKeyPair::Secp256k1(signer) => signer.signer(),
            SignerKeyPair::Eip191(signer) => signer.signer(),
        }
    }

    // This is for testing purposes, shortcut to get the guid of the signer to avoid having to make extra imports
    fn into_guid(self: @SignerKeyPair) -> felt252 {
        self.signer().into_guid()
    }

    fn sign(self: @SignerKeyPair, message_hash: felt252) -> SignerSignature {
        match self {
            SignerKeyPair::Starknet(signer) => signer.sign(message_hash),
            SignerKeyPair::Secp256r1(signer) => signer.sign(message_hash),
            SignerKeyPair::Secp256k1(signer) => signer.sign(message_hash),
            SignerKeyPair::Eip191(signer) => signer.sign(message_hash),
        }
    }
}

// Impl for each signer type
pub trait SignerKeyPairTestTrait<T> {
    type Signer;
    type Signature;

    fn random() -> T;
    fn from_secret(secret: felt252) -> T;
    fn signer_concrete(self: @T) -> Self::Signer;
    fn signer(self: @T) -> Signer;
    // This is for testing purposes, shortcut to get the guid of the signer to avoid having to make extra imports
    fn into_guid(self: @T) -> felt252 {
        Self::signer(self).into_guid()
    }
    fn sign_concrete(self: @T, message_hash: felt252) -> Self::Signature;
    fn sign(self: @T, message_hash: felt252) -> SignerSignature;
}


pub impl StarknetKeyPair of SignerKeyPairTestTrait<StarknetSignerKeyPair> {
    type Signer = StarknetSigner;
    type Signature = StarknetSignature;

    fn random() -> StarknetSignerKeyPair {
        StarknetSignerKeyPair { key_pair: KeyPairTrait::generate() }
    }

    fn from_secret(secret: felt252) -> StarknetSignerKeyPair {
        StarknetSignerKeyPair { key_pair: KeyPairTrait::from_secret_key(secret) }
    }

    fn signer_concrete(self: @StarknetSignerKeyPair) -> Self::Signer {
        StarknetSigner { pubkey: (*self).key_pair.public_key.try_into().unwrap() }
    }

    fn signer(self: @StarknetSignerKeyPair) -> Signer {
        Signer::Starknet(self.signer_concrete())
    }

    fn sign_concrete(self: @StarknetSignerKeyPair, message_hash: felt252) -> Self::Signature {
        let (r, s): (felt252, felt252) = (*self.key_pair).sign(message_hash).unwrap();
        StarknetSignature { r, s }
    }

    fn sign(self: @StarknetSignerKeyPair, message_hash: felt252) -> SignerSignature {
        let signature = self.sign_concrete(message_hash);
        SignerSignature::Starknet(((*self).signer_concrete(), signature))
    }
}

pub impl Secp256r1KeyPair of SignerKeyPairTestTrait<Secp256r1SignerKeyPair> {
    type Signer = Secp256r1Signer;
    type Signature = Signature;

    fn random() -> Secp256r1SignerKeyPair {
        Secp256r1SignerKeyPair { key_pair: KeyPairTrait::generate() }
    }

    fn from_secret(secret: felt252) -> Secp256r1SignerKeyPair {
        Secp256r1SignerKeyPair { key_pair: KeyPairTrait::from_secret_key(secret.into()) }
    }

    fn signer_concrete(self: @Secp256r1SignerKeyPair) -> Self::Signer {
        let (pubkey, _) = (*self.key_pair).public_key.get_coordinates().unwrap();
        Secp256r1Signer { pubkey: pubkey.try_into().unwrap() }
    }

    fn signer(self: @Secp256r1SignerKeyPair) -> Signer {
        Signer::Secp256r1(self.signer_concrete())
    }

    fn sign_concrete(self: @Secp256r1SignerKeyPair, message_hash: felt252) -> Self::Signature {
        let message_hash: u256 = message_hash.into();
        secp256_sign_message(*self.key_pair, message_hash)
    }

    fn sign(self: @Secp256r1SignerKeyPair, message_hash: felt252) -> SignerSignature {
        let signature = self.sign_concrete(message_hash);
        SignerSignature::Secp256r1(((*self).signer_concrete(), signature))
    }
}

pub impl Secp256k1KeyPair of SignerKeyPairTestTrait<Secp256k1SignerKeyPair> {
    type Signer = Secp256k1Signer;
    type Signature = Signature;

    fn random() -> Secp256k1SignerKeyPair {
        Secp256k1SignerKeyPair { key_pair: KeyPairTrait::generate() }
    }

    fn from_secret(secret: felt252) -> Secp256k1SignerKeyPair {
        Secp256k1SignerKeyPair { key_pair: KeyPairTrait::from_secret_key(secret.into()) }
    }

    fn signer_concrete(self: @Secp256k1SignerKeyPair) -> Self::Signer {
        let pubkey_hash = public_key_point_to_eth_address::<Secp256k1Point>((*self.key_pair).public_key);
        Secp256k1Signer { pubkey_hash }
    }

    fn signer(self: @Secp256k1SignerKeyPair) -> Signer {
        Signer::Secp256k1(self.signer_concrete())
    }

    fn sign_concrete(self: @Secp256k1SignerKeyPair, message_hash: felt252) -> Self::Signature {
        let message_hash: u256 = message_hash.into();
        secp256_sign_message(*self.key_pair, message_hash)
    }

    fn sign(self: @Secp256k1SignerKeyPair, message_hash: felt252) -> SignerSignature {
        let signature = self.sign_concrete(message_hash);
        SignerSignature::Secp256k1(((*self).signer_concrete(), signature))
    }
}

pub impl Eip191KeyPair of SignerKeyPairTestTrait<Eip191SignerKeyPair> {
    type Signer = Eip191Signer;
    type Signature = Signature;

    fn random() -> Eip191SignerKeyPair {
        Eip191SignerKeyPair { key_pair: Secp256k1KeyPair::random() }
    }

    fn from_secret(secret: felt252) -> Eip191SignerKeyPair {
        Eip191SignerKeyPair { key_pair: Secp256k1KeyPair::from_secret(secret) }
    }

    fn signer_concrete(self: @Eip191SignerKeyPair) -> Self::Signer {
        let concrete_type = (*self.key_pair).signer_concrete();
        Eip191Signer { eth_address: concrete_type.pubkey_hash }
    }

    fn signer(self: @Eip191SignerKeyPair) -> Signer {
        Signer::Eip191(self.signer_concrete())
    }

    fn sign_concrete(self: @Eip191SignerKeyPair, message_hash: felt252) -> Self::Signature {
        let eip191_hash = calculate_eip191_hash(message_hash);
        secp256_sign_message(*self.key_pair.key_pair, eip191_hash)
    }

    fn sign(self: @Eip191SignerKeyPair, message_hash: felt252) -> SignerSignature {
        let signature = self.sign_concrete(message_hash);
        SignerSignature::Eip191(((*self).signer_concrete(), signature))
    }
}

fn secp256_sign_message<
    T,
    +SnForgeSignerTrait<KeyPair<u256, T>, u256, (u256, u256)>,
    +Secp256PointTrait<T>,
    +Secp256Trait<T>,
    +Drop<T>,
    +Copy<T>,
>(
    key_pair: KeyPair<u256, T>, message_hash: u256,
) -> Signature {
    let (r, s) = key_pair.sign(message_hash).unwrap();
    let (pubkey_y_true, _) = recover_public_key::<T>(message_hash, Signature { r, s, y_parity: true })
        .unwrap()
        .get_coordinates()
        .unwrap();
    let (pubkey, _) = key_pair.public_key.get_coordinates().unwrap();
    let raw_signature = Signature { r, s, y_parity: pubkey_y_true == pubkey };
    // Normalize the signature
    let curve_size = Secp256Trait::<T>::get_curve_size();
    if raw_signature.s > curve_size / 2 {
        Signature { r: raw_signature.r, s: curve_size - raw_signature.s, y_parity: !raw_signature.y_parity }
    } else {
        raw_signature
    }
}
