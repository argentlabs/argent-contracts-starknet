use argent::signer::webauthn::{
    WebauthnAssertion, get_webauthn_hash, verify_client_data_json, verify_authenticator_data
};
use core::array::ArrayTrait;
use ecdsa::check_ecdsa_signature;
use hash::{HashStateTrait, HashStateExTrait, Hash};
use poseidon::{PoseidonTrait, HashState};
use starknet::SyscallResultTrait;
use starknet::secp256_trait::{Secp256PointTrait, Signature as Secp256r1Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::Secp256r1Point;
use starknet::{EthAddress, eth_signature::{Signature as Secp256k1Signature, is_eth_signature_valid}};

#[derive(Drop, Copy, Serde, PartialEq)]
struct StarknetSignature {
    r: felt252,
    s: felt252,
}

// TODO This should be `pubkey: NonZero<felt252>` where relevant
#[derive(Drop, Copy, Serde, PartialEq)]
struct StarknetSigner {
    pubkey: NonZero<felt252>
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct Secp256k1Signer {
    pubkey_hash: EthAddress
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct Secp256r1Signer {
    pubkey: u256
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnSigner {
    origin: felt252,
    rp_id_hash: u256,
    pubkey: u256
}

#[derive(Drop, Copy, Serde, PartialEq)]
enum Signer {
    Starknet: StarknetSigner,
    Secp256k1: Secp256k1Signer,
    Secp256r1: Secp256r1Signer,
    Webauthn: WebauthnSigner
}


#[inline(always)]
fn starknetSignerFromPubKey(pubkey: felt252) -> Signer {
    Signer::Starknet(StarknetSigner { pubkey: pubkey.try_into().expect('argent/zero-pubkey') })
}


trait SignerTrait<T> {
    fn is_reasonable(self: T) -> bool;
    fn into_guid(self: T) -> felt252;
}

impl SignerTraitImpl of SignerTrait<Signer> {
    fn is_reasonable(self: Signer) -> bool {
        match self {
            Signer::Starknet(signer) => true,
            Signer::Secp256k1(signer) => !signer.pubkey_hash.is_zero(),
            Signer::Secp256r1(signer) => !signer.pubkey.is_zero(),
            Signer::Webauthn(signer) => !signer.origin.is_zero()
                && !signer.rp_id_hash.is_zero()
                && !signer.pubkey.is_zero(),
        }
    }

    fn into_guid(self: Signer) -> felt252 {
        match self {
            Signer::Starknet(signer) => signer
                .pubkey
                .into(), //PoseidonTrait::new().update_with(('Stark', signer.pubkey)).finalize(),
            Signer::Secp256k1(signer) => PoseidonTrait::new().update_with(('Secp256k1', signer.pubkey_hash)).finalize(),
            Signer::Secp256r1(signer) => PoseidonTrait::new().update_with(('Secp256r1', signer.pubkey)).finalize(),
            Signer::Webauthn(signer) => PoseidonTrait::new()
                .update_with(('Webauthn', signer.origin, signer.rp_id_hash, signer.pubkey))
                .finalize(),
        }
    }
}

/// Enum of the different signature type supported.
/// For each type the variant contains a signer and an associated signature.
#[derive(Drop, Copy, Serde, PartialEq)]
enum SignerSignature {
    Starknet: (StarknetSigner, StarknetSignature),
    Secp256k1: (Secp256k1Signer, Secp256k1Signature),
    Secp256r1: (Secp256r1Signer, Secp256r1Signature),
    Webauthn: (WebauthnSigner, WebauthnAssertion),
}

trait SignerSignatureTrait {
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool;
    fn signer(self: SignerSignature) -> Signer;
    fn signer_into_guid(self: SignerSignature) -> felt252;
}

impl SignerSignatureImpl of SignerSignatureTrait {
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool {
        match self {
            SignerSignature::Starknet((signer, signature)) => is_valid_starknet_signature(hash, signer, signature),
            SignerSignature::Secp256k1((
                signer, signature
            )) => is_valid_secp256k1_signature(hash.into(), signer, signature),
            SignerSignature::Secp256r1((
                signer, signature
            )) => is_valid_secp256r1_signature(hash.into(), signer, signature),
            SignerSignature::Webauthn((signer, signature)) => is_valid_webauthn_signature(hash, signer, signature),
        }
    }

    fn signer(self: SignerSignature) -> Signer {
        match self {
            SignerSignature::Starknet((signer, _)) => Signer::Starknet(signer),
            SignerSignature::Secp256k1((signer, _)) => Signer::Secp256k1(signer),
            SignerSignature::Secp256r1((signer, _)) => Signer::Secp256r1(signer),
            SignerSignature::Webauthn((signer, _)) => Signer::Webauthn(signer)
        }
    }

    // TODO Why not re-use into_guid trait and impl it?
    #[inline(always)]
    fn signer_into_guid(self: SignerSignature) -> felt252 {
        self.signer().into_guid()
    }
}

fn is_valid_starknet_signature(hash: felt252, signer: StarknetSigner, signature: StarknetSignature) -> bool {
    check_ecdsa_signature(hash, signer.pubkey.into(), signature.r, signature.s)
}

fn is_valid_secp256k1_signature(hash: u256, signer: Secp256k1Signer, signature: Secp256k1Signature) -> bool {
    is_eth_signature_valid(hash, signature, signer.pubkey_hash).is_ok()
}

fn is_valid_secp256r1_signature(hash: u256, signer: Secp256r1Signer, signature: Secp256r1Signature) -> bool {
    let recovered = recover_public_key::<Secp256r1Point>(hash, signature).expect('argent/invalid-sig-format');
    let (recovered_signer, _) = recovered.get_coordinates().expect('argent/invalid-sig-format');
    recovered_signer == signer.pubkey
}

fn is_valid_webauthn_signature(hash: felt252, signer: WebauthnSigner, assertion: WebauthnAssertion) -> bool {
    verify_client_data_json(@assertion, hash, signer.origin);
    verify_authenticator_data(assertion.authenticator_data, signer.rp_id_hash);

    let signed_hash = get_webauthn_hash(@assertion);
    is_valid_secp256r1_signature(signed_hash, Secp256r1Signer { pubkey: signer.pubkey }, assertion.signature)
}
