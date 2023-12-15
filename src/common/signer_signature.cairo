use argent::common::webauthn::{Assertion, Parse, get_webauthn_hash, verify_client_data_json, verify_authenticator_data};
use array::ArrayTrait;
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

/// Enum of the different signature type supported.
/// For each type the variant contains the signer (or public key) and the signature associated to the signer.
#[derive(Drop, Copy, Serde, PartialEq)]
enum SignerSignature {
    #[default]
    Starknet: (felt252, StarknetSignature),
    Secp256k1: (felt252, Secp256k1Signature),
    Secp256r1: (u256, Secp256r1Signature),
    Webauthn: (u256, Assertion),
}

trait Validate {
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool;
}

trait Felt252Signer {
    fn signer_as_felt252(self: SignerSignature) -> felt252;
}

impl ValidateImpl of Validate {
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
}

impl Felt252SignerImpl of Felt252Signer {
    fn signer_as_felt252(self: SignerSignature) -> felt252 {
        match self {
            SignerSignature::Starknet((signer, signature)) => signer,
            SignerSignature::Secp256k1((signer, signature)) => signer,
            SignerSignature::Secp256r1((
                signer, signature
            )) => {
                let hash_state = PoseidonTrait::new();
                hash_state.update_with(signer).finalize()
            },
            SignerSignature::Webauthn((
                signer, signature
            )) => {
                let origin = signature.origin();
                let rp_id_hash = signature.rp_id_hash();
                let hash_state = PoseidonTrait::new();
                hash_state.update_with((origin, rp_id_hash, signer)).finalize()
            },
        }
    }
}

fn is_valid_starknet_signature(hash: felt252, signer: felt252, signature: StarknetSignature) -> bool {
    check_ecdsa_signature(hash, signer, signature.r, signature.s)
}

fn is_valid_secp256k1_signature(hash: u256, signer: felt252, signature: Secp256k1Signature) -> bool {
    let eth_signer: EthAddress = signer.try_into().expect('argent/invalid-eth-signer');
    is_eth_signature_valid(hash, signature, eth_signer).is_ok()
}

fn is_valid_secp256r1_signature(hash: u256, signer: u256, signature: Secp256r1Signature) -> bool {
    let recovered = recover_public_key::<Secp256r1Point>(hash, signature).expect('argent/invalid-sig-format');
    let (recovered_signer, _) = recovered.get_coordinates().expect('argent/invalid-sig-format');
    recovered_signer == signer
}

fn is_valid_webauthn_signature(hash: felt252, signer: u256, assertion: Assertion) -> bool {
    verify_client_data_json(@assertion, hash);
    verify_authenticator_data(assertion.authenticator_data);

    let signed_hash = get_webauthn_hash(assertion);
    is_valid_secp256r1_signature(signed_hash, signer, assertion.signature)
}
