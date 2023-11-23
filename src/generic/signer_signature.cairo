use ecdsa::check_ecdsa_signature;
use starknet::{EthAddress, eth_signature::is_eth_signature_valid, secp256_trait::signature_from_vrs};

#[derive(Drop, Copy, Serde, PartialEq)]
enum SignerType {
    #[default]
    Starknet,
    // TODO ADD SIGNATURE: Secp256k1(Signature)
    Secp256k1,
    Webauthn,
    Secp256r1,
}

#[derive(Copy, Drop, Serde)]
struct SignerSignature {
    signer: felt252,
    signer_type: SignerType,
    signature: Span<felt252>,
}

fn assert_valid_starknet_signature(hash: felt252, signer: felt252, signature: Span<felt252>) {
    assert(signature.len() == 2, 'argent/invalid-signature');
    let is_valid = check_ecdsa_signature(hash, signer, *signature[0], *signature[1]);
    assert(is_valid, 'argent/invalid-stark-signature');
}

fn assert_valid_ethereum_signature(hash: felt252, signer: felt252, mut signature: Span<felt252>) {
    assert(signature.len() == 5, 'argent/invalid-signature');
    let eth_signer: EthAddress = signer.try_into().expect('argent/invalid-eth-signer');
    let signature_r: u256 = Serde::deserialize(ref signature).expect('argent/invalid-eth-r');
    let signature_s: u256 = Serde::deserialize(ref signature).expect('argent/invalid-eth-s');
    let signature_v: u32 = Serde::deserialize(ref signature).expect('argent/invalid-eth-v');

    let eth_signature = signature_from_vrs(signature_v, signature_r, signature_s);

    match is_eth_signature_valid(hash.into(), eth_signature, eth_signer) {
        Result::Ok(_) => {},
        Result::Err(err) => panic_with_felt252('argent/invalid-eth-signature'),
    }
}
