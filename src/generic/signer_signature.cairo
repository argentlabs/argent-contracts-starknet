use ecdsa::check_ecdsa_signature;
use starknet::secp256k1::{Secp256k1Point, Secp256k1PointImpl};
use starknet::{
    EthAddress, Felt252TryIntoEthAddress, verify_eth_signature,
    secp256_trait::{Signature, signature_from_vrs, Secp256Trait, Secp256PointTrait}
};

#[derive(Drop, Copy, Serde, PartialEq)]
enum SignerType {
    Starknet,
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

fn deserialize_array_signer_signature(mut serialized: Span<felt252>) -> Option<Span<SignerSignature>> {
    let mut output = array![];
    loop {
        if serialized.len() == 0 {
            break Option::Some(output.span());
        }
        match Serde::deserialize(ref serialized) {
            Option::Some(signer_signature) => output.append(signer_signature),
            Option::None => { break Option::None; },
        };
    }
}

fn assert_valid_starknet_signature(hash: felt252, signer: felt252, signature: Span<felt252>) {
    assert(signature.len() == 2, 'argent/invalid-signature');
    let is_valid = check_ecdsa_signature(hash, signer, *signature.at(0), *signature.at(1));
    assert(is_valid, 'argent/invalid-signature');
}

fn assert_valid_ethereum_signature(hash: felt252, signer: felt252, signature: Span<felt252>) {
    assert(signature.len() == 3, 'argent/invalid-signature');
    let eth_signer: EthAddress = signer.try_into().unwrap();
    let signature_r: u256 = (*signature.at(0)).into();
    let signature_s: u256 = (*signature.at(1)).into();
    let signature_v: u32 = (*signature.at(2)).try_into().unwrap();
    let eth_signature = signature_from_vrs(signature_v, signature_r, signature_s);
    let eth_hash: u256 = hash.into();
    verify_eth_signature(eth_hash, eth_signature, eth_signer);
}
