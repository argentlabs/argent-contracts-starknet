use argent::common::account::{IAccount, IAccountDispatcher, IAccountDispatcherTrait};
use argent::generic::{signer_signature::{SignerSignature, SignerType}, {argent_generic::ArgentGenericAccount}};
use core::serde::Serde;

use debug::PrintTrait;
use starknet::{deploy_syscall, VALIDATED};

const message_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;
const message_hash_eth: u256 = 0x50d988b67c11bd72ecf5fe3524ff5dae2c9fecae384c9522dc9e1265685aa76b;

const owner_pubkey: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const owner_r: felt252 = 0x6ff7b413a8457ef90f326b5280600a4473fef49b5b1dcdfcd7f42ca7aa59c69;
const owner_s: felt252 = 0x23a9747ed71abc5cb956c0df44ee8638b65b3e9407deade65de62247b8fd77;


const owner_pubkey_eth: felt252 = 0x3da5e1F7B6D63E9982A6c26D8eCFd8219654E087;
const owner_eth_r: u256 = 0x1ae7851de289a255edf1719e131e9836bde174fc916d2a0614fac6fce67bb9a3;
const owner_eth_s: u256 = 0x23c3521217bfa6d585193ba4b92b2fb60ec8182ed1bf211279a6e307e8d6fbfd;
const owner_eth_v: felt252 = 28;


fn double_signature(r1: felt252, s1: felt252, r2: felt252, s2: felt252) -> Array<felt252> {
    array![r1, s1, r2, s2]
}

fn single_signature(r: felt252, s: felt252) -> Array<felt252> {
    array![r, s]
}

fn initialize_account(owner: felt252) -> IAccountDispatcher {
    let calldata = array![1, 1, owner];
    let class_hash = ArgentGenericAccount::TEST_CLASS_HASH.try_into().unwrap();
    let (contract_address, _) = deploy_syscall(class_hash, 0, calldata.span(), true).unwrap();

    IAccountDispatcher { contract_address }
}

#[test]
#[available_gas(2000000)]
fn test_valid_signature_starknet() {
    let mut signatures = array![];
    let signer_signature = SignerSignature {
        signer: owner_pubkey, signer_type: SignerType::Starknet, signature: array![owner_r, owner_s].span()
    };
    signer_signature.serialize(ref signatures);
    assert(
        initialize_account(owner_pubkey).is_valid_signature(message_hash, signatures) == VALIDATED, 'invalid signature'
    );
}

#[test]
#[available_gas(2000000000)]
fn test_valid_signature_secp256k1() {
    let mut signature = array![];
    let hash: u256 = message_hash_eth.into();
    let high: felt252 = hash.high.into();
    high.serialize(ref signature);
    owner_eth_r.serialize(ref signature);
    owner_eth_s.serialize(ref signature);
    owner_eth_v.serialize(ref signature);
    let signer_signature = SignerSignature {
        signer: owner_pubkey_eth, signer_type: SignerType::Secp256k1, signature: signature.span()
    };

    let mut signatures = array![];
    signer_signature.serialize(ref signatures);
    assert(
        initialize_account(owner_pubkey_eth).is_valid_signature(hash.low.into(), signatures) == VALIDATED,
        'invalid signature'
    );
}
