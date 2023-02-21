use contracts::asserts;

use starknet_testing::set_caller_address;
use starknet_testing::set_contract_address;
use starknet::contract_address_const;


#[test]
#[available_gas(2000000)]
fn test_assert_only_self() {
    set_caller_address(contract_address_const::<42>());
    set_contract_address(contract_address_const::<42>());
    asserts::assert_only_self();
}

#[test]
#[should_panic]
fn test_assert_only_self_panic() {
    set_caller_address(contract_address_const::<42>());
    set_contract_address(contract_address_const::<69>());
    asserts::assert_only_self();
}

#[test]
fn assert_correct_tx_version_test() {
    // for now valid tx_version == 1 & 2
    let tx_version = 1;
    asserts::assert_correct_tx_version(tx_version);
}

#[test]
#[should_panic]
fn assert_correct_tx_version_invalidtx_test() {
    // for now valid tx_version == 1 & 2
    let tx_version = 4;
    asserts::assert_correct_tx_version(tx_version);
    let tx_version = 4;
    asserts::assert_correct_tx_version(tx_version);
}
