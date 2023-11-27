use ecdsa::check_ecdsa_signature;
use starknet::{EthAddress, eth_signature::{Signature, is_eth_signature_valid}, secp256_trait::signature_from_vrs};

#[derive(Drop, Copy, Serde, PartialEq)]
struct StarknetSignature {
    r: felt252,
    s: felt252,
}

#[derive(Drop, Copy, Serde, PartialEq)]
enum SignerType {
    #[default]
    Starknet: StarknetSignature,
    Secp256k1: Signature,
    Webauthn,
    Secp256r1,
}

#[derive(Copy, Drop, Serde)]
struct SignerSignature {
    signer: felt252,
    signer_type: SignerType,
}

fn assert_valid_starknet_signature(hash: felt252, signer: felt252, signature: StarknetSignature) {
    let is_valid = check_ecdsa_signature(hash, signer, signature.r, signature.s);
    assert(is_valid, 'argent/invalid-stark-signature');
}

fn assert_valid_ethereum_signature(hash: felt252, signer: felt252, signature: Signature) {
    let eth_signer: EthAddress = signer.try_into().expect('argent/invalid-eth-signer');
    match is_eth_signature_valid(hash.into(), signature, eth_signer) {
        Result::Ok(_) => {},
        Result::Err(err) => panic_with_felt252('argent/invalid-eth-signature'),
    }
}
