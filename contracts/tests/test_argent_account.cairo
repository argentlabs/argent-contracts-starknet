use starknet::contract_address_const;
use starknet::testing::set_caller_address;
use zeroable::Zeroable;

use contracts::ArgentAccount;

use contracts::tests::initialize_account;
use contracts::tests::initialize_account_without_guardian;
use contracts::tests::initialize_account_with_guardian_backup;
use contracts::tests::signer_pubkey;
use contracts::tests::guardian_pubkey;
use contracts::tests::guardian_backup_pubkey;

const ERC165_INVALID_INTERFACE_ID: felt252 = 0xffffffff;

#[test]
#[available_gas(2000000)]
fn initialize() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_signer() == 1, 'value should be 1');
    assert(ArgentAccount::get_guardian() == 2, 'value should be 2');
    assert(ArgentAccount::get_guardian_backup() == 3, 'value should be 3');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/null-signer', ))]
fn initialize_with_null_signer() {
    ArgentAccount::initialize(0, 2, 3);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/already-initialized', ))]
fn already_initialized() {
    ArgentAccount::initialize(1, 2, 3);
    ArgentAccount::initialize(10, 20, 0);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/backup-should-be-null', ))]
fn initialized_guardian_to_zero_without_guardian_backup() {
    ArgentAccount::initialize(1, 0, 3);
}


#[test]
#[available_gas(2000000)]
fn initialized_no_guardian_no_backup() {
    ArgentAccount::initialize(1, 0, 0);
    assert(ArgentAccount::get_signer() == 1, 'value should be 1');
    assert(ArgentAccount::get_guardian() == 0, 'guardian should be zero');
    assert(ArgentAccount::get_guardian_backup() == 0, 'guardian backup should be zero');
}

#[test]
#[available_gas(2000000)]
fn erc165_unsupported_interfaces() {
    assert(ArgentAccount::supports_interface(0) == false, 'value should be false');
    assert(
        !ArgentAccount::supports_interface(ERC165_INVALID_INTERFACE_ID), 'value should be false'
    );
}

#[test]
#[available_gas(2000000)]
fn erc165_supported_interfaces() {
    let value = ArgentAccount::supports_interface(ArgentAccount::ERC165_IERC165_INTERFACE_ID);
    assert(value, 'value should be true');
    let value = ArgentAccount::supports_interface(ArgentAccount::ERC165_ACCOUNT_INTERFACE_ID);
    assert(value, 'value should be true');
    let value = ArgentAccount::supports_interface(ArgentAccount::ERC165_OLD_ACCOUNT_INTERFACE_ID);
    assert(value, 'value should be true');
}

#[test]
#[available_gas(2000000)]
fn change_signer() {
    initialize_account();
    assert(ArgentAccount::get_signer() == signer_pubkey, 'value should be 1');
    ArgentAccount::change_signer(11);
    assert(ArgentAccount::get_signer() == 11, 'value should be 11');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/only-self', ))]
fn change_signer_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::change_signer(11);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/null-signer', ))]
fn change_signer_to_zero() {
    initialize_account();
    ArgentAccount::change_signer(0);
}

#[test]
#[available_gas(2000000)]
fn change_guardian() {
    initialize_account();
    ArgentAccount::change_guardian(22);
    assert(ArgentAccount::get_guardian() == 22, 'value should be 22');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/only-self', ))]
fn change_guardian_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::change_guardian(22);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/backup-should-be-null', ))]
fn change_guardian_to_zero() {
    initialize_account_with_guardian_backup();
    ArgentAccount::change_guardian(0);
}

#[test]
#[available_gas(2000000)]
fn change_guardian_to_zero_without_guardian_backup() {
    initialize_account();
    ArgentAccount::change_guardian(0);
    assert(ArgentAccount::get_guardian().is_zero(), 'value should be 0');
}

#[test]
#[available_gas(2000000)]
fn change_guardian_backup() {
    initialize_account();
    ArgentAccount::change_guardian_backup(33);
    assert(ArgentAccount::get_guardian_backup() == 33, 'value should be 33');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/only-self', ))]
fn change_guardian_backup_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::change_guardian_backup(22);
}

#[test]
#[available_gas(2000000)]
fn change_guardian_backup_to_zero() {
    initialize_account();
    ArgentAccount::change_guardian_backup(0);
    assert(ArgentAccount::get_guardian_backup().is_zero(), 'value should be 0');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/guardian-required', ))]
fn change_invalid_guardian_backup() {
    initialize_account_without_guardian();
    ArgentAccount::change_guardian_backup(33);
}


#[test]
fn get_name() {
    assert(ArgentAccount::get_name() == 'ArgentAccount', 'Name should be ArgentAccount');
}

#[test]
fn get_version() {
    assert(ArgentAccount::get_version() == '0.3.0-alpha.1', 'Name should be 0.3.0-alpha.1');
}
