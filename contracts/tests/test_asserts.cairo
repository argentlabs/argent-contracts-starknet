use array::ArrayTrait;
use zeroable::Zeroable;
use contracts::asserts;
use contracts::argent_account::ArgentAccount::Call;

use starknet_testing::set_caller_address;
use starknet_testing::set_contract_address;
use starknet::contract_address_const;
use starknet::get_contract_address;

impl CallDrop of Drop::<Call>;
impl ArrayCallDrop of Drop::<Array::<Call>>;

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

#[test]
#[available_gas(2000000)]
fn test_no_self_call() {
    let self = starknet::get_contract_address();
    assert(self.is_zero(), 'non null');
    let mut calls = ArrayTrait::new();
    asserts::assert_no_self_call(@calls, self);
    let mut calls = ArrayTrait::new();
    calls.append(
        Call { to: contract_address_const::<1>(), selector: 100, calldata: ArrayTrait::new() }
    );
    asserts::assert_no_self_call(@calls, self);
    let mut calls = ArrayTrait::new();
    calls.append(
        Call { to: contract_address_const::<2>(), selector: 100, calldata: ArrayTrait::new() }
    );
    calls.append(
        Call { to: contract_address_const::<3>(), selector: 200, calldata: ArrayTrait::new() }
    );
    asserts::assert_no_self_call(@calls, self);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/no-multicall-to-self', ))]
fn test_no_self_call_invalid() {
    let self = starknet::get_contract_address();
    let mut calls = ArrayTrait::new();
    calls.append(Call { to: self, selector: 100, calldata: ArrayTrait::new() });
    asserts::assert_no_self_call(@calls, self);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/no-multicall-to-self', ))]
fn test_no_self_call_invalid_2() {
    let self = starknet::get_contract_address();
    let mut calls = ArrayTrait::new();
    calls.append(
        Call { to: contract_address_const::<1>(), selector: 100, calldata: ArrayTrait::new() }
    );
    calls.append(Call { to: self, selector: 200, calldata: ArrayTrait::new() });
    asserts::assert_no_self_call(@calls, self);
}
