use contracts::ArgentAccount;

const ERC165_INVALID_INTERFACE_ID: felt = 0xffffffff;

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
#[should_panic(expected = 'argent: signer cannot be null')]
fn initialize_with_null_signer() {
    ArgentAccount::initialize(0, 2, 3);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = 'argent: already initialized')]
fn already_initialized() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_signer() == 1, 'value should be 1');
    ArgentAccount::initialize(10, 20, 0);
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
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_signer() == 1, 'value should be 1');
    ArgentAccount::change_signer(11);
    assert(ArgentAccount::get_signer() == 11, 'value should be 11');
}

#[test]
#[available_gas(2000000)]
fn change_guardian() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_guardian() == 2, 'value should be 2');
    ArgentAccount::change_guardian(22);
    assert(ArgentAccount::get_guardian() == 22, 'value should be 22');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = 'argent: new guardian invalid')]
fn change_invalid_guardian() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_guardian() == 2, 'value should be 2');
    ArgentAccount::change_guardian(0);
}

#[test]
#[available_gas(2000000)]
fn change_guardian_backup() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_guardian_backup() == 3, 'value should be 3');
    ArgentAccount::change_guardian_backup(33);
    assert(ArgentAccount::get_guardian_backup() == 33, 'value should be 33');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = 'argent: guardian required')]
fn change_invalid_guardian_backup() {
    ArgentAccount::initialize(1, 0, 0);
    ArgentAccount::change_guardian_backup(33);
}
