use starknet::contract_address_const;
use starknet::testing::set_caller_address;
use zeroable::Zeroable;
use array::ArrayTrait;

use account::ArgentAccount;

use account::tests::initialize_account;
use account::tests::initialize_account_without_guardian;
use account::tests::owner_pubkey;
use account::tests::wrong_owner_pubkey;
use account::tests::guardian_pubkey;
use account::tests::single_signature;

const new_owner_pubkey: felt252 = 0xa7da05a4d664859ccd6e567b935cdfbfe3018c7771cb980892ef38878ae9bc;
const new_owner_r: felt252 = 0x5b786ea6339eae95e7fbcabc43b4667f697738581f9762108515aea7a051342;
const new_owner_s: felt252 = 0x4ded483cee51e8237a6f1c38e75042c1055ebdc22d3394d84b657f42cbdf32b;

const wrong_owner_r: felt252 = 0x4be5db0599a2e5943f207da3f9bf2dd091acf055b71a1643e9c35fcd7e2c0df;
const wrong_owner_s: felt252 = 0x2e44d5bad55a0d692e02529e7060f352fde85fae8d5946f28c34a10a29bc83b;

#[test]
#[available_gas(2000000)]
fn initialize() {
    ArgentAccount::constructor(1, 2);
    assert(ArgentAccount::get_owner() == 1, 'value should be 1');
    assert(ArgentAccount::get_guardian() == 2, 'value should be 2');
    assert(ArgentAccount::get_guardian_backup() == 0, 'value should be 0');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/null-owner', ))]
fn initialize_with_null_owner() {
    ArgentAccount::constructor(0, 2);
}

#[test]
#[available_gas(2000000)]
fn initialized_no_guardian_no_backup() {
    ArgentAccount::constructor(1, 0);
    assert(ArgentAccount::get_owner() == 1, 'value should be 1');
    assert(ArgentAccount::get_guardian() == 0, 'guardian should be zero');
    assert(ArgentAccount::get_guardian_backup() == 0, 'guardian backup should be zero');
}

#[test]
#[available_gas(2000000)]
fn erc165_unsupported_interfaces() {
    assert(!ArgentAccount::supports_interface(0), 'Should not support 0');
    assert(!ArgentAccount::supports_interface(0xffffffff), 'Should not support 0xffffffff');
}

#[test]
#[available_gas(2000000)]
fn erc165_supported_interfaces() {
    assert(ArgentAccount::supports_interface(0x01ffc9a7), 'ERC165_IERC165_INTERFACE_ID');
    assert(ArgentAccount::supports_interface(0xa66bd575), 'ERC165_ACCOUNT_INTERFACE_ID');
    assert(ArgentAccount::supports_interface(0x3943f10f), 'ERC165_OLD_ACCOUNT_INTERFACE_ID');
}

#[test]
#[available_gas(2000000)]
fn change_owner() {
    initialize_account();
    assert(ArgentAccount::get_owner() == owner_pubkey, 'value should be 1');

    let new_owner_sig = single_signature(new_owner_r, new_owner_s);
    ArgentAccount::change_owner(new_owner_pubkey, new_owner_sig);
    assert(ArgentAccount::get_owner() == new_owner_pubkey, 'value should be new owner pub');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', ))]
fn change_owner_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    let new_owner_sig = single_signature(new_owner_r, new_owner_s);
    ArgentAccount::change_owner(new_owner_pubkey, new_owner_sig);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/null-owner', ))]
fn change_owner_to_zero() {
    initialize_account();
    let new_owner_sig = single_signature(new_owner_r, new_owner_s);
    ArgentAccount::change_owner(0, new_owner_sig);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-owner-sig', ))]
fn change_owner_invalid_message() {
    initialize_account();
    let new_owner_sig = single_signature(wrong_owner_r, wrong_owner_s);
    ArgentAccount::change_owner(new_owner_pubkey, new_owner_sig);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-owner-sig', ))]
fn change_owner_wrong_pub_key() {
    initialize_account();
    let new_owner_sig = single_signature(new_owner_r, new_owner_s);
    ArgentAccount::change_owner(wrong_owner_pubkey, new_owner_sig);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-signature-length', ))]
fn change_owner_invalid_sig_length() {
    initialize_account();
    let mut new_owner_sig = ArrayTrait::new();
    new_owner_sig.append(new_owner_r);
    new_owner_sig.append(new_owner_s);
    new_owner_sig.append(1);
    ArgentAccount::change_owner(wrong_owner_pubkey, new_owner_sig);
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
#[should_panic(expected: ('argent/only-self', ))]
fn change_guardian_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::change_guardian(22);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/backup-should-be-null', ))]
fn change_guardian_to_zero() {
    ArgentAccount::constructor(owner_pubkey, guardian_pubkey);
    ArgentAccount::_guardian_backup::write(42);
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
#[should_panic(expected: ('argent/only-self', ))]
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
#[should_panic(expected: ('argent/guardian-required', ))]
fn change_invalid_guardian_backup() {
    initialize_account_without_guardian();
    ArgentAccount::change_guardian_backup(33);
}

#[test]
fn get_version() {
    let version = ArgentAccount::get_version();
    assert(version.major == 0, 'Version major = 0');
    assert(version.minor == 3, 'Version minor = 3');
    assert(version.patch == 0, 'Version patch = 0');
}

#[test]
fn getVersion() {
    assert(ArgentAccount::getVersion() == '0.3.0', 'Version should be 0.3.0');
}

#[test]
fn get_name() {
    assert(ArgentAccount::get_name() == 'ArgentAccount', 'Name should be ArgentAccount');
}

#[test]
fn getName() {
    assert(ArgentAccount::get_name() == 'ArgentAccount', 'Name should be ArgentAccount');
}

#[test]
#[available_gas(2000000)]
fn unsuported_supportsInterface() {
    assert(ArgentAccount::supportsInterface(0) == 0, 'value should be false');
    assert(ArgentAccount::supportsInterface(0xffffffff) == 0, 'Should not support 0xffffffff');
}

#[test]
#[available_gas(2000000)]
fn supportsInterface() {
    assert(ArgentAccount::supportsInterface(0x01ffc9a7) == 1, 'ERC165_IERC165_INTERFACE_ID');
    assert(ArgentAccount::supportsInterface(0xa66bd575) == 1, 'ERC165_ACCOUNT_INTERFACE_ID');
    assert(ArgentAccount::supportsInterface(0x3943f10f) == 1, 'ERC165_OLD_ACCOUNT_INTERFACE_ID');
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
