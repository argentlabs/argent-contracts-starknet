use argent::utils::asserts;
use snforge_std::{start_prank, CheatTarget, test_address};
use starknet::get_contract_address;
use starknet::{contract_address_const, testing::{set_caller_address, set_contract_address}, account::Call};

#[test]
fn test_assert_only_self() {
    start_prank(CheatTarget::All, test_address());
    asserts::assert_only_self();
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_assert_only_self_panic() {
    start_prank(CheatTarget::All, 42.try_into().unwrap());
    asserts::assert_only_self();
}

#[test]
fn test_no_self_call_empty() {
    let self = contract_address_const::<42>();
    start_prank(CheatTarget::All, self);
    let calls = array![];
    asserts::assert_no_self_call(calls.span(), self);
}

#[test]
fn test_no_self_call_1() {
    let self = contract_address_const::<42>();
    start_prank(CheatTarget::All, self);
    let call1 = Call { to: contract_address_const::<1>(), selector: 100, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1].span(), self);
}

#[test]
fn test_no_self_call_2() {
    let self = contract_address_const::<42>();
    start_prank(CheatTarget::All, self);
    let call1 = Call { to: contract_address_const::<2>(), selector: 100, calldata: array![].span() };
    let call2 = Call { to: contract_address_const::<3>(), selector: 200, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1, call2].span(), self);
}

#[test]
#[should_panic(expected: ('argent/no-multicall-to-self',))]
fn test_no_self_call_invalid() {
    let self = contract_address_const::<42>();
    start_prank(CheatTarget::All, self);
    let call = Call { to: self, selector: 100, calldata: array![].span() };
    asserts::assert_no_self_call(array![call].span(), self);
}

#[test]
#[should_panic(expected: ('argent/no-multicall-to-self',))]
fn test_no_self_call_invalid_2() {
    let self = contract_address_const::<42>();
    start_prank(CheatTarget::All, self);
    let call1 = Call { to: contract_address_const::<1>(), selector: 100, calldata: array![].span() };
    let call2 = Call { to: self, selector: 200, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1, call2].span(), self);
}

