use ecdsa::check_ecdsa_signature;
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

// #[derive(Drop, Copy, Serde, PartialEq)]
// enum Signer {
//     Starknet: felt252,
//     Secp256k1: felt252,
//     Secp256r1: u256,
//     Webauthn,
// }

/// Enum of the different signature type supported.
/// For each type the variant contains the signer (or public key) and the signature associated to the signer.
#[derive(Drop, Copy, Serde, PartialEq)]
enum SignerSignature {
    #[default]
    Starknet: (felt252, StarknetSignature),
    Secp256k1: (felt252, Secp256k1Signature),
    Secp256r1: (felt252, Secp256r1Signature),
    Webauthn,
}

trait Validate {
    fn is_valid_signer(self: SignerSignature, target: felt252) -> bool;
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool;
}

trait Felt252Signer {
    fn signer_as_felt252(self: SignerSignature) -> felt252;
}

impl ValidateImpl of Validate {
    fn is_valid_signer(self: SignerSignature, target: felt252) -> bool {
        match self {
            SignerSignature::Starknet((signer, signature)) => target == signer,
            SignerSignature::Secp256k1((signer, signature)) => target == signer,
            SignerSignature::Secp256r1((signer, signature)) => target == signer,
            SignerSignature::Webauthn => false,
        }
    }

    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool {
        match self {
            SignerSignature::Starknet((signer, signature)) => is_valid_starknet_signature(hash, signer, signature),
            SignerSignature::Secp256k1((signer, signature)) => is_valid_secp256k1_signature(hash, signer, signature),
            SignerSignature::Secp256r1((signer, signature)) => is_valid_secp256r1_signature(hash, signer, signature),
            SignerSignature::Webauthn => false,
        }
    }
}

impl Felt252SignerImpl of Felt252Signer {
    fn signer_as_felt252(self: SignerSignature) -> felt252 {
        match self {
            SignerSignature::Starknet((signer, signature)) => signer,
            SignerSignature::Secp256k1((signer, signature)) => signer,
            SignerSignature::Secp256r1((signer, signature)) => signer,
            SignerSignature::Webauthn => 0,
        }
    }
}

fn is_valid_starknet_signature(hash: felt252, signer: felt252, signature: StarknetSignature) -> bool {
    check_ecdsa_signature(hash, signer, signature.r, signature.s)
}

fn is_valid_secp256k1_signature(hash: felt252, signer: felt252, signature: Secp256k1Signature) -> bool {
    let eth_signer: EthAddress = signer.try_into().expect('argent/invalid-eth-signer');
    is_eth_signature_valid(hash.into(), signature, eth_signer).is_ok()
}

fn is_valid_secp256r1_signature(hash: felt252, owner: felt252, signature: Secp256r1Signature) -> bool {
    let recovered = recover_public_key::<Secp256r1Point>(hash.into(), signature).expect('argent/invalid-sig-format');
    let (recovered_x, _) = recovered.get_coordinates().expect('argent/invalid-sig-format');
    let recovered_owner = truncate_felt252(recovered_x);
    recovered_owner == owner
}

fn truncate_felt252(value: u256) -> felt252 {
    // using 248-bit mask instead of 251-bit mask to only remove characters from hex representation instead of modifying digits
    let value = value & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    value.try_into().expect('truncate_felt252 failed')
}
