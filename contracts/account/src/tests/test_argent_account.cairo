use array::ArrayTrait;
use option::OptionTrait;
use result::ResultTrait;
use traits::TryInto;
use zeroable::Zeroable;

use starknet::{
    contract_address_const, deploy_syscall, testing::{set_version, set_contract_address}
};

use account::{
    ArgentAccount,
    tests::{
        ITestArgentAccountDispatcherTrait, owner_pubkey, wrong_owner_pubkey,
        initialize_account_with, initialize_account, initialize_account_without_guardian,
    }
};

const new_owner_pubkey: felt252 = 0xa7da05a4d664859ccd6e567b935cdfbfe3018c7771cb980892ef38878ae9bc;
const new_owner_r: felt252 = 0x3e242301b001c97a5be2b3a165fae7abf72027cb8b1ca4713580d52d9ff008e;
const new_owner_s: felt252 = 0x758f108a8beed1dec98d054740287611882d7633bb1b94c73728aaff777bf6c;

const wrong_owner_r: felt252 = 0x4be5db0599a2e5943f207da3f9bf2dd091acf055b71a1643e9c35fcd7e2c0df;
const wrong_owner_s: felt252 = 0x2e44d5bad55a0d692e02529e7060f352fde85fae8d5946f28c34a10a29bc83b;

#[test]
#[available_gas(2000000)]
fn initialize() {
    let account = initialize_account_with(1, 2);
    assert(account.get_owner() == 1, 'value should be 1');
    assert(account.get_guardian() == 2, 'value should be 2');
    assert(account.get_guardian_backup() == 0, 'value should be 0');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-tx-version', 'ENTRYPOINT_FAILED'))]
fn check_transaction_version_on_execute() {
    let account = initialize_account();
    set_contract_address(contract_address_const::<0>());
    set_version(32);
    account.__execute__(ArrayTrait::new());
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-tx-version', 'ENTRYPOINT_FAILED'))]
fn check_transaction_version_on_validate() {
    let account = initialize_account();
    set_contract_address(contract_address_const::<0>());
    set_version(32);
    account.__validate__(ArrayTrait::new());
}

#[test]
#[available_gas(2000000)]
fn initialize_with_null_owner() {
    let mut calldata = ArrayTrait::new();
    calldata.append(0);
    calldata.append(12);
    let mut err = deploy_syscall(
        ArgentAccount::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .unwrap_err();
    assert(@err.pop_front().unwrap() == @'argent/null-owner', 'Should be argent/null-owner');
}
#[test]
#[available_gas(2000000)]
fn initialized_no_guardian_no_backup() {
    let account = initialize_account_with(1, 0);
    assert(account.get_owner() == 1, 'value should be 1');
    assert(account.get_guardian() == 0, 'guardian should be zero');
    assert(account.get_guardian_backup() == 0, 'guardian backup should be zero');
}

#[test]
#[available_gas(2000000)]
fn erc165_unsupported_interfaces() {
    let account = initialize_account();
    assert(!account.supports_interface(0), 'Should not support 0');
    assert(!account.supports_interface(0xffffffff), 'Should not support 0xffffffff');
}

#[test]
#[available_gas(2000000)]
fn erc165_supported_interfaces() {
    let account = initialize_account();
    assert(account.supports_interface(0x01ffc9a7), 'ERC165_IERC165_INTERFACE_ID');
    assert(account.supports_interface(0xa66bd575), 'ERC165_ACCOUNT_INTERFACE_ID');
    assert(account.supports_interface(0x3943f10f), 'ERC165_OLD_ACCOUNT_INTERFACE_ID');
}

#[test]
#[available_gas(2000000)]
fn change_owner() {
    let account = initialize_account();
    assert(account.get_owner() == owner_pubkey, 'value should be 1');

    set_contract_address(contract_address_const::<1>());
    account.change_owner(new_owner_pubkey, new_owner_r, new_owner_s);
    assert(account.get_owner() == new_owner_pubkey, 'value should be new owner pub');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', 'ENTRYPOINT_FAILED'))]
fn change_owner_only_self() {
    let account = initialize_account();
    set_contract_address(contract_address_const::<42>());
    account.change_owner(new_owner_pubkey, new_owner_r, new_owner_s);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/null-owner', 'ENTRYPOINT_FAILED'))]
fn change_owner_to_zero() {
    let account = initialize_account();
    initialize_account();
    account.change_owner(0, new_owner_r, new_owner_s);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-owner-sig', 'ENTRYPOINT_FAILED'))]
fn change_owner_invalid_message() {
    let account = initialize_account();
    account.change_owner(new_owner_pubkey, wrong_owner_r, wrong_owner_s);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-owner-sig', 'ENTRYPOINT_FAILED'))]
fn change_owner_wrong_pub_key() {
    let account = initialize_account();
    account.change_owner(wrong_owner_pubkey, new_owner_r, new_owner_s);
}

#[test]
#[available_gas(2000000)]
fn change_guardian() {
    let account = initialize_account();
    account.change_guardian(22);
    assert(account.get_guardian() == 22, 'value should be 22');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', 'ENTRYPOINT_FAILED'))]
fn change_guardian_only_self() {
    let account = initialize_account();
    set_contract_address(contract_address_const::<42>());
    account.change_guardian(22);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/backup-should-be-null', 'ENTRYPOINT_FAILED'))]
fn change_guardian_to_zero() {
    let account = initialize_account();
    account.change_guardian_backup(42);
    account.change_guardian(0);
}

#[test]
#[available_gas(2000000)]
fn change_guardian_to_zero_without_guardian_backup() {
    let account = initialize_account();
    account.change_guardian(0);
    assert(account.get_guardian().is_zero(), 'value should be 0');
}

#[test]
#[available_gas(2000000)]
fn change_guardian_backup() {
    let account = initialize_account();
    account.change_guardian_backup(33);
    assert(account.get_guardian_backup() == 33, 'value should be 33');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', 'ENTRYPOINT_FAILED'))]
fn change_guardian_backup_only_self() {
    let account = initialize_account();
    set_contract_address(contract_address_const::<42>());
    account.change_guardian_backup(22);
}

#[test]
#[available_gas(2000000)]
fn change_guardian_backup_to_zero() {
    let account = initialize_account();
    account.change_guardian_backup(0);
    assert(account.get_guardian_backup().is_zero(), 'value should be 0');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/guardian-required', 'ENTRYPOINT_FAILED'))]
fn change_invalid_guardian_backup() {
    let account = initialize_account_without_guardian();
    account.change_guardian_backup(33);
}

#[test]
#[available_gas(2000000)]
fn get_version() {
    let version = initialize_account().get_version();
    assert(version.major == 0, 'Version major = 0');
    assert(version.minor == 3, 'Version minor = 3');
    assert(version.patch == 0, 'Version patch = 0');
}

#[test]
#[available_gas(2000000)]
fn getVersion() {
    assert(initialize_account().getVersion() == '0.3.0', 'Version should be 0.3.0');
}

#[test]
#[available_gas(2000000)]
fn get_name() {
    assert(initialize_account().get_name() == 'ArgentAccount', 'Name should be ArgentAccount');
}

#[test]
#[available_gas(2000000)]
fn getName() {
    assert(initialize_account().getName() == 'ArgentAccount', 'Name should be ArgentAccount');
}
#[test]
#[available_gas(2000000)]
fn unsuported_supportsInterface() {
    let account = initialize_account();
    assert(account.supportsInterface(0) == 0, 'value should be false');
    assert(account.supportsInterface(0xffffffff) == 0, 'Should not support 0xffffffff');
}

#[test]
#[available_gas(2000000)]
fn supportsInterface() {
    let account = initialize_account();
    assert(account.supportsInterface(0x01ffc9a7) == 1, 'ERC165_IERC165_INTERFACE_ID');
    assert(account.supportsInterface(0xa66bd575) == 1, 'ERC165_ACCOUNT_INTERFACE_ID');
    assert(account.supportsInterface(0x3943f10f) == 1, 'ERC165_OLD_ACCOUNT_INTERFACE_ID');
}

#[test]
#[available_gas(2000000)]
fn test_selectors() {
    // Double check to ensure it IS and STAYS correct
    assert(
        ArgentAccount::TRIGGER_ESCAPE_GUARDIAN_SELECTOR == 73865429733192804476769961144708816295126306469589518371407068321865763651,
        'trigger_escape_guardian'
    );
    assert(
        ArgentAccount::TRIGGER_ESCAPE_OWNER_SELECTOR == 1099763735485822105046709698985960101896351570185083824040512300972207240555,
        'trigger_escape_owner'
    );
    assert(
        ArgentAccount::ESCAPE_GUARDIAN_SELECTOR == 1662889347576632967292303062205906116436469425870979472602094601074614456040,
        'escape_guardian'
    );
    assert(
        ArgentAccount::ESCAPE_OWNER_SELECTOR == 1621457541430776841129472853859989177600163870003012244140335395142204209277,
        'escape_owner'
    );
    assert(
        ArgentAccount::EXECUTE_AFTER_UPGRADE_SELECTOR == 738349667340360233096752603318170676063569407717437256101137432051386874767,
        'execute_after_upgrade'
    );
}

