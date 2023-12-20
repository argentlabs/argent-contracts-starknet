use argent::common::webauthn::{
    WebauthnAssertion, get_webauthn_hash, verify_client_data_json, verify_authenticator_data
};
use core::hash::HashStateExTrait;
use ecdsa::check_ecdsa_signature;
use hash::{HashStateTrait, Hash};
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

#[derive(Drop, Copy, Serde, PartialEq)]
struct StarknetSigner {
    pubkey: felt252
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct Secp256k1Signer {
    pubkey: felt252
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

impl SignerIntoFelt252 of Into<Signer, felt252> {
    fn into(self: Signer) -> felt252 {
        match self {
            Signer::Starknet(signer) => signer.into(),
            Signer::Secp256k1(signer) => signer.into(),
            Signer::Secp256r1(signer) => signer.into(),
            Signer::Webauthn(signer) => signer.into(),
        }
    }
}

impl StarknetSignerIntoFelt252 of Into<StarknetSigner, felt252> {
    fn into(self: StarknetSigner) -> felt252 {
        self.pubkey
    }
}

impl Secp256k1SignerIntoFelt252 of Into<Secp256k1Signer, felt252> {
    fn into(self: Secp256k1Signer) -> felt252 {
        PoseidonTrait::new().update_with(('Secp256k1', self.pubkey)).finalize()
    }
}

impl Secp256r1SignerIntoFelt252 of Into<Secp256r1Signer, felt252> {
    fn into(self: Secp256r1Signer) -> felt252 {
        PoseidonTrait::new().update_with(('Secp256r1', self.pubkey)).finalize()
    }
}

impl WebauthnSignerIntoFelt252 of Into<WebauthnSigner, felt252> {
    fn into(self: WebauthnSigner) -> felt252 {
        PoseidonTrait::new().update_with(('Webauthn', self.origin, self.rp_id_hash, self.pubkey)).finalize()
    }
}

impl SignerZero of Zeroable<Signer> {
    fn zero() -> Signer {
        Signer::Starknet(StarknetSigner { pubkey: 0 })
    }
    #[inline(always)]
    fn is_zero(self: Signer) -> bool {
        match self {
            Signer::Starknet(signer) => signer.pubkey.is_zero(),
            Signer::Secp256k1(signer) => signer.pubkey.is_zero(),
            Signer::Secp256r1(signer) => signer.pubkey.is_zero(),
            Signer::Webauthn(signer) => signer.pubkey.is_zero(),
        }
    }
    #[inline(always)]
    fn is_non_zero(self: Signer) -> bool {
        !self.is_zero()
    }
}

/// Enum of the different signature type supported.
/// For each type the variant contains a signer and an associated signature.
#[derive(Drop, Copy, Serde, PartialEq)]
enum SignerSignature {
    #[default]
    Starknet: (StarknetSigner, StarknetSignature),
    Secp256k1: (Secp256k1Signer, Secp256k1Signature),
    Secp256r1: (Secp256r1Signer, Secp256r1Signature),
    Webauthn: (WebauthnSigner, WebauthnAssertion),
}

trait SignerSignatureTrait {
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool;
    fn signer_as_felt252(self: SignerSignature) -> felt252;
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

    fn signer_as_felt252(self: SignerSignature) -> felt252 {
        match self {
            SignerSignature::Starknet((signer, signature)) => signer.into(),
            SignerSignature::Secp256k1((signer, signature)) => signer.into(),
            SignerSignature::Secp256r1((signer, signature)) => signer.into(),
            SignerSignature::Webauthn((signer, signature)) => signer.into()
        }
    }
}

fn is_valid_starknet_signature(hash: felt252, signer: StarknetSigner, signature: StarknetSignature) -> bool {
    check_ecdsa_signature(hash, signer.pubkey, signature.r, signature.s)
}

fn is_valid_secp256k1_signature(hash: u256, signer: Secp256k1Signer, signature: Secp256k1Signature) -> bool {
    let eth_signer: EthAddress = signer.pubkey.try_into().expect('argent/invalid-eth-signer');
    is_eth_signature_valid(hash, signature, eth_signer).is_ok()
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
