use argent::account::argent_account::ArgentAccount;
use argent::common::signer_signature::{Signer, StarknetSigner};
use argent_tests::setup::account_test_setup::{
    ITestArgentAccountDispatcher, ITestArgentAccountDispatcherTrait, owner_pubkey, guardian_pubkey, wrong_owner_pubkey,
    wrong_guardian_pubkey, initialize_account, initialize_account_without_guardian, initialize_account_with
};
use argent_tests::setup::utils::to_starknet_signer_signatures;
use starknet::VALIDATED;

const message_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

const owner_r: felt252 = 0x6ff7b413a8457ef90f326b5280600a4473fef49b5b1dcdfcd7f42ca7aa59c69;
const owner_s: felt252 = 0x23a9747ed71abc5cb956c0df44ee8638b65b3e9407deade65de62247b8fd77;

const guardian_r: felt252 = 0x1734f5510c8b862984461d2221411d12a706140bae629feac0aad35f4d91a19;
const guardian_s: felt252 = 0x75c904c1969e5b2bf2e9fedb32d6180f06288d81a6a2164d876ea4be2ae7520;

const guardian_backup_pubkey: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;
const guardian_backup_r: felt252 = 0x1e03a158a4142532f903caa32697a74fcf5c05b762bb866cec28670d0a53f9a;
const guardian_backup_s: felt252 = 0x74be76fe620a42899bc34afce7b31a058408b23c250805054fca4de4e0121ca;

const wrong_owner_r: felt252 = 0x4be5db0599a2e5943f207da3f9bf2dd091acf055b71a1643e9c35fcd7e2c0df;
const wrong_owner_s: felt252 = 0x2e44d5bad55a0d692e02529e7060f352fde85fae8d5946f28c34a10a29bc83b;

const wrong_guardian_r: felt252 = 0x5e5375b33d31fea164fb58c97ae0f9354863af5274f47a261b268b072285539;
const wrong_guardian_s: felt252 = 0x649c2cc2696a1f257534f03d913f869daae675467ed2f994b94059341e68929;

#[test]
#[available_gas(2000000)]
fn valid_no_guardian() {
    let signatures = to_starknet_signer_signatures(array![owner_pubkey, owner_r, owner_s]);
    assert(
        initialize_account_without_guardian().is_valid_signature(message_hash, signatures) == VALIDATED,
        'invalid signature'
    );
}

#[test]
#[available_gas(20000000)]
fn valid_with_guardian() {
    let signatures = to_starknet_signer_signatures(
        array![owner_pubkey, owner_r, owner_s, guardian_pubkey, guardian_r, guardian_s]
    );
    assert(initialize_account().is_valid_signature(message_hash, signatures) == VALIDATED, 'invalid signature');
}

#[test]
#[available_gas(20000000)]
fn valid_with_guardian_backup() {
    let account = initialize_account_with(owner_pubkey, 1);
    let guardian_backup = Signer::Starknet(StarknetSigner { pubkey: guardian_backup_pubkey });
    account.change_guardian_backup(guardian_backup);
    let signatures = to_starknet_signer_signatures(
        array![owner_pubkey, owner_r, owner_s, guardian_backup_pubkey, guardian_backup_r, guardian_backup_s]
    );
    assert(account.is_valid_signature(message_hash, signatures) == VALIDATED, 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_hash_1() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(array![owner_pubkey, owner_r, owner_s]);
    assert(account.is_valid_signature(0, signatures) == 0, 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_hash_2() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(array![owner_pubkey, owner_r, owner_s]);
    assert(account.is_valid_signature(123, signatures) == 0, 'invalid signature');
}

#[test]
#[available_gas(20000000)]
fn invalid_owner_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(array![0, 0, 0]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature');
    let signatures = to_starknet_signer_signatures(array![wrong_owner_pubkey, wrong_owner_r, wrong_owner_s]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature');
    let signatures = to_starknet_signer_signatures(array![guardian_pubkey, guardian_backup_r, guardian_backup_s]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature');
}

#[test]
#[available_gas(20000000)]
fn invalid_owner_with_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![0, 0, 0, guardian_pubkey, guardian_r, guardian_s]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature');
    let signatures = to_starknet_signer_signatures(
        array![wrong_owner_pubkey, wrong_owner_r, wrong_owner_s, guardian_pubkey, guardian_r, guardian_s]
    );
    account.is_valid_signature(message_hash, signatures);
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(
        array![guardian_pubkey, guardian_r, guardian_s, guardian_pubkey, guardian_r, guardian_s]
    );
}

#[test]
#[available_gas(20000000)]
fn valid_owner_with_invalid_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![owner_pubkey, owner_r, owner_s, 0, 0, 0]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 1');
    let signatures = to_starknet_signer_signatures(array![owner_pubkey, owner_r, owner_s, 25, 42, 69]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 2');
    let signatures = to_starknet_signer_signatures(
        array![owner_pubkey, owner_r, owner_s, wrong_guardian_pubkey, wrong_guardian_r, wrong_guardian_s]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 3');
    let signatures = to_starknet_signer_signatures(
        array![owner_pubkey, owner_r, owner_s, owner_pubkey, owner_r, owner_s]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 4');
}

#[test]
#[available_gas(30000000)]
fn invalid_owner_with_invalid_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![0, 0, 0, 0, 0, 0]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 1');
    let signatures = to_starknet_signer_signatures(array![2, 42, 99, 6, 534, 123]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 2');
    let signatures = to_starknet_signer_signatures(array![wrong_owner_pubkey, wrong_owner_r, wrong_owner_s, 0, 0, 0]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 3');
    let signatures = to_starknet_signer_signatures(
        array![0, 0, 0, wrong_guardian_pubkey, wrong_guardian_r, wrong_guardian_s]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 4');
    let signatures = to_starknet_signer_signatures(
        array![
            wrong_owner_pubkey, wrong_owner_r, wrong_owner_s, wrong_guardian_pubkey, wrong_guardian_r, wrong_guardian_s
        ]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 5');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/undeserializable', 'ENTRYPOINT_FAILED'))]
fn invalid_empty_signature_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = array![];
    account.is_valid_signature(message_hash, signatures);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/invalid-signature-length', 'ENTRYPOINT_FAILED'))]
fn invalid_signature_length_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(
        array![owner_pubkey, owner_r, owner_s, guardian_pubkey, guardian_r, guardian_s]
    );
    account.is_valid_signature(message_hash, signatures);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/undeserializable', 'ENTRYPOINT_FAILED'))]
fn invalid_empty_signature_with_guardian() {
    let account = initialize_account();
    let signatures = array![];
    account.is_valid_signature(message_hash, signatures);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-signature-length', 'ENTRYPOINT_FAILED'))]
fn invalid_signature_length_with_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![owner_pubkey, owner_r, owner_s]);
    account.is_valid_signature(message_hash, signatures);
}

