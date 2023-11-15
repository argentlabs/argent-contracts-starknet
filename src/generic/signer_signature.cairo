use core::option::OptionTrait;
use core::traits::TryInto;
use ecdsa::check_ecdsa_signature;
use starknet::{EthAddress, verify_eth_signature, secp256_trait::signature_from_vrs};

#[derive(Drop, Copy, Serde, PartialEq)]
enum SignerType {
    #[default]
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
    let is_valid = check_ecdsa_signature(hash, signer, *signature[0], *signature[1]);
    assert(is_valid, 'argent/invalid-ecdsa-signature');
}

fn assert_valid_ethereum_signature(hash: felt252, signer: felt252, mut signature: Span<felt252>) {
    assert(signature.len() == 5, 'argent/invalid-signature');
    let eth_signer: EthAddress = signer.try_into().unwrap();
    let signature_r: u256 = Serde::deserialize(ref signature).unwrap();
    let signature_s: u256 = Serde::deserialize(ref signature).unwrap();
    let signature_v: u32 = Serde::deserialize(ref signature).unwrap();

    let eth_signature = signature_from_vrs(signature_v, signature_r, signature_s);

    verify_eth_signature(hash.into(), eth_signature, eth_signer);
}
