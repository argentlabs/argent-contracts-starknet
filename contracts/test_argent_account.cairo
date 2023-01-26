use contracts::ArgentAccount;

const ERC165_INVALID_INTERFACE_ID: felt = 0xffffffff;

#[test]
#[available_gas(20000)]
fn initialize() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_signer() == 1, 'value should be 1');
    assert(ArgentAccount::get_guardian() == 2, 'value should be 2');
    assert(ArgentAccount::get_guardian_backup() == 3, 'value should be 3');
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: signer cannot be null')]
fn initialize_with_null_signer() {
    ArgentAccount::initialize(0, 2, 3);
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: already initialized')]
fn already_initialized() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_signer() == 1, 'value should be 1');
    ArgentAccount::initialize(10, 20, 0);
}

#[test]
#[available_gas(20000)]
fn erc165_unsupported_interfaces() {
    assert(ArgentAccount::supportsInterface(0) == false, 'value should be false');
    assert(ArgentAccount::supportsInterface(ERC165_INVALID_INTERFACE_ID) == false, 'value should be false');
}

#[test]
#[available_gas(20000)]
fn erc165_supported_interfaces() {
    assert(ArgentAccount::supportsInterface(ArgentAccount::ERC165_IERC165_INTERFACE_ID) == true, 'value should be true');
    assert(ArgentAccount::supportsInterface(ArgentAccount::ERC165_ACCOUNT_INTERFACE_ID) == true, 'value should be true');
    assert(ArgentAccount::supportsInterface(ArgentAccount::ERC165_OLD_ACCOUNT_INTERFACE_ID) == true, 'value should be true');
}


#[test]
#[available_gas(20000)]
fn get_contract_address_test() {
    assert(ArgentAccount::get_contract_address_test() == 69, 'value should be 69');
}

#[test]
#[available_gas(20000)]
fn test_assert_only_self() {
    let retdata = ArgentAccount::assert_only_self_test();
    assert(retdata == 1, 'return data should be 1');
}

#[test]
#[available_gas(20000)]
fn assert_correct_tx_version_test() {
    let tx_version = 1;
    let retdata = ArgentAccount::assert_correct_tx_version_test(tx_version);
    assert(retdata == 1, 'return data should be 1');
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: guardian required')]
fn assert_guardian_set_test() {
    let retdata = ArgentAccount::assert_guardian_set_test();
    assert(retdata != 1, 'return data should not be 1');
}