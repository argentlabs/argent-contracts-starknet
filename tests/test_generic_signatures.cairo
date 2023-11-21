use argent::common::account::{IAccount, IAccountDispatcher, IAccountDispatcherTrait};
use argent::generic::{signer_signature::{SignerSignature, SignerType}, {argent_generic::ArgentGenericAccount}};

use starknet::{deploy_syscall, VALIDATED};

const message_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

const owner_pubkey: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const owner_r: felt252 = 0x6ff7b413a8457ef90f326b5280600a4473fef49b5b1dcdfcd7f42ca7aa59c69;
const owner_s: felt252 = 0x23a9747ed71abc5cb956c0df44ee8638b65b3e9407deade65de62247b8fd77;

const owner_pubkey_eth: felt252 = 0x3da5e1F7B6D63E9982A6c26D8eCFd8219654E087;
const owner_eth_r: u256 = 0xc259f65857e922d06c40a0c436697125394a9e825d61804630bb099005c611be;
const owner_eth_s: u256 = 0x098cf1c540ad542653979ae9eef9e0c8f53a68f4868d9057e2a193f69526c061;
const owner_eth_v: felt252 = 27;

fn initialize_account(owner: felt252) -> IAccountDispatcher {
    let calldata = array![1, 1, owner];
    let class_hash = ArgentGenericAccount::TEST_CLASS_HASH.try_into().unwrap();
    let (contract_address, _) = deploy_syscall(class_hash, 0, calldata.span(), true).unwrap();

    IAccountDispatcher { contract_address }
}

#[test]
#[available_gas(2000000)]
fn test_valid_signature_starknet() {
    let mut signatures = array![1];
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
    owner_eth_r.serialize(ref signature);
    owner_eth_s.serialize(ref signature);
    owner_eth_v.serialize(ref signature);
    let signer_signature = SignerSignature {
        signer: owner_pubkey_eth, signer_type: SignerType::Secp256k1, signature: signature.span()
    };

    let mut signatures = array![1];
    signer_signature.serialize(ref signatures);
    assert(
        initialize_account(owner_pubkey_eth).is_valid_signature(message_hash, signatures) == VALIDATED,
        'invalid signature'
    );
}
