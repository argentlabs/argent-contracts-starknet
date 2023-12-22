use argent::common::{
    account::{IAccount, IAccountDispatcher, IAccountDispatcherTrait},
    signer_signature::{
        SignerSignatureTrait, SignerSignature, StarknetSignature, StarknetSigner, Secp256k1Signer, Secp256r1Signer,
        WebauthnSigner, IntoGuid
    },
    serialization::serialize,
};
use argent::generic::{argent_generic::ArgentGenericAccount};
use argent_tests::setup::webauthn_test_setup::{setup_1, setup_2, setup_3, setup_4,};
use starknet::EthAddress;
use starknet::{deploy_syscall, VALIDATED, eth_signature::Signature};

const message_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

const owner_pubkey: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const owner_r: felt252 = 0x6ff7b413a8457ef90f326b5280600a4473fef49b5b1dcdfcd7f42ca7aa59c69;
const owner_s: felt252 = 0x23a9747ed71abc5cb956c0df44ee8638b65b3e9407deade65de62247b8fd77;

const owner_pubkey_eth: felt252 = 0x3da5e1F7B6D63E9982A6c26D8eCFd8219654E087;
const owner_eth_r: u256 = 0xc259f65857e922d06c40a0c436697125394a9e825d61804630bb099005c611be;
const owner_eth_s: u256 = 0x098cf1c540ad542653979ae9eef9e0c8f53a68f4868d9057e2a193f69526c061;
const owner_eth_v: u32 = 27;

fn initialize_account(owner: felt252) -> IAccountDispatcher {
    let calldata = array![1, 1, owner];
    let class_hash = ArgentGenericAccount::TEST_CLASS_HASH.try_into().unwrap();
    let (contract_address, _) = deploy_syscall(class_hash, 0, calldata.span(), true).unwrap();

    IAccountDispatcher { contract_address }
}

#[test]
#[available_gas(2000000000)]
fn test_valid_signature_starknet() {
    let signer_signature = SignerSignature::Starknet(
        (StarknetSigner { pubkey: owner_pubkey }, StarknetSignature { r: owner_r, s: owner_s })
    );
    let signatures = array![signer_signature];
    assert(
        initialize_account(owner_pubkey).is_valid_signature(message_hash, serialize(@signatures)) == VALIDATED,
        'invalid signature'
    );
}

#[test]
#[available_gas(3000000000)]
fn test_valid_signature_secp256k1() {
    let signer_signature = SignerSignature::Secp256k1(
        (
            Secp256k1Signer { pubkey_hash: EthAddress { address: owner_pubkey_eth } },
            Signature { r: owner_eth_r, s: owner_eth_s, y_parity: owner_eth_v % 2 == 0 }
        )
    );
    let signer_guid = signer_signature.signer_into_guid().unwrap();
    let signatures = array![signer_signature];
    assert(
        initialize_account(signer_guid).is_valid_signature(message_hash, serialize(@signatures)) == VALIDATED,
        'invalid signature'
    );
}

#[test]
#[available_gas(2000000000)]
fn test_valid_signature_webauthn_1() {
    let (challenge, signer, assertion) = setup_1();
    let signatures = array![SignerSignature::Webauthn((signer, assertion))];

    assert(
        initialize_account(signer.into_guid().unwrap())
            .is_valid_signature(challenge, serialize(@signatures)) == VALIDATED,
        'invalid signature'
    );
}

#[test]
#[available_gas(2000000000)]
fn test_valid_signature_webauthn_2() {
    let (challenge, signer, assertion) = setup_2();
    let signatures = array![SignerSignature::Webauthn((signer, assertion))];

    assert(
        initialize_account(signer.into_guid().unwrap())
            .is_valid_signature(challenge, serialize(@signatures)) == VALIDATED,
        'invalid signature'
    );
}

#[test]
#[available_gas(2000000000)]
fn test_valid_signature_webauthn_3() {
    let (challenge, signer, assertion) = setup_3();
    let signatures = array![SignerSignature::Webauthn((signer, assertion))];

    assert(
        initialize_account(signer.into_guid().unwrap())
            .is_valid_signature(challenge, serialize(@signatures)) == VALIDATED,
        'invalid signature'
    );
}

#[test]
#[available_gas(2000000000)]
fn test_valid_signature_webauthn_4() {
    let (challenge, signer, assertion) = setup_4();
    let signatures = array![SignerSignature::Webauthn((signer, assertion))];

    assert(
        initialize_account(signer.into_guid().unwrap())
            .is_valid_signature(challenge, serialize(@signatures)) == VALIDATED,
        'invalid signature'
    );
}
