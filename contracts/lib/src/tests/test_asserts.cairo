use array::ArrayTrait;
use zeroable::Zeroable;
use starknet::testing::set_caller_address;
use starknet::testing::set_contract_address;
use starknet::contract_address_const;
use starknet::get_contract_address;

use lib::asserts;
use lib::Call;

#[test]
#[available_gas(2000000)]
fn test_assert_only_self() {
    set_caller_address(contract_address_const::<42>());
    set_contract_address(contract_address_const::<42>());
    asserts::assert_only_self();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', ))]
fn test_assert_only_self_panic() {
    set_caller_address(contract_address_const::<42>());
    set_contract_address(contract_address_const::<69>());
    asserts::assert_only_self();
}

#[test]
fn assert_correct_tx_version() {
    asserts::assert_correct_tx_version(1);
}

#[test]
fn assert_correct_tx_version_query_version() {
    asserts::assert_correct_tx_version(340282366920938463463374607431768211457);
}

#[test]
#[should_panic(expected: ('argent/invalid-tx-version', ))]
fn assert_correct_tx_version_invalid_tx() {
    asserts::assert_correct_tx_version(4);
}

#[test]
#[available_gas(2000000)]
fn test_no_self_call_empty() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let calls = ArrayTrait::new();
    asserts::assert_no_self_call(calls.span(), self);
}

#[test]
#[available_gas(2000000)]
fn test_no_self_call_1() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let mut calls = ArrayTrait::new();
    let call1 = Call {
        to: contract_address_const::<1>(), selector: 100, calldata: ArrayTrait::new()
    };
    calls.append(call1);
    asserts::assert_no_self_call(calls.span(), self);
}

#[test]
#[available_gas(2000000)]
fn test_no_self_call_2() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let mut calls = ArrayTrait::new();
    let call1 = Call {
        to: contract_address_const::<2>(), selector: 100, calldata: ArrayTrait::new()
    };
    let call2 = Call {
        to: contract_address_const::<3>(), selector: 200, calldata: ArrayTrait::new()
    };
    calls.append(call1);
    calls.append(call2);
    asserts::assert_no_self_call(calls.span(), self);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/no-multicall-to-self', ))]
fn test_no_self_call_invalid() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let mut calls = ArrayTrait::new();
    calls.append(Call { to: self, selector: 100, calldata: ArrayTrait::new() });
    asserts::assert_no_self_call(calls.span(), self);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/no-multicall-to-self', ))]
fn test_no_self_call_invalid_2() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let mut calls = ArrayTrait::new();
    let call1 = Call {
        to: contract_address_const::<1>(), selector: 100, calldata: ArrayTrait::new()
    };
    calls.append(call1);
    calls.append(Call { to: self, selector: 200, calldata: ArrayTrait::new() });
    asserts::assert_no_self_call(calls.span(), self);
}
