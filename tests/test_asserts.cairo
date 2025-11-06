use argent::utils::asserts;
use snforge_std::{start_cheat_caller_address_global, test_address};
use starknet::account::Call;

#[test]
fn test_assert_only_self() {
    start_cheat_caller_address_global(test_address());
    asserts::assert_only_self();
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_assert_only_self_panic() {
    start_cheat_caller_address_global(42.try_into().unwrap());
    asserts::assert_only_self();
}

#[test]
fn test_no_self_call_empty() {
    let self = 42.try_into().unwrap();
    start_cheat_caller_address_global(self);
    let calls = array![];
    asserts::assert_no_self_call(calls.span(), self);
}

#[test]
fn test_no_self_call_1() {
    let self = 42.try_into().unwrap();
    start_cheat_caller_address_global(self);
    let call1 = Call { to: 1.try_into().unwrap(), selector: 100, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1].span(), self);
}

#[test]
fn test_no_self_call_2() {
    let self = 42.try_into().unwrap();
    start_cheat_caller_address_global(self);
    let call1 = Call { to: 2.try_into().unwrap(), selector: 100, calldata: array![].span() };
    let call2 = Call { to: 3.try_into().unwrap(), selector: 200, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1, call2].span(), self);
}

#[test]
#[should_panic(expected: ('argent/no-multicall-to-self',))]
fn test_no_self_call_invalid() {
    let self = 42.try_into().unwrap();
    start_cheat_caller_address_global(self);
    let call = Call { to: self, selector: 100, calldata: array![].span() };
    asserts::assert_no_self_call(array![call].span(), self);
}

#[test]
#[should_panic(expected: ('argent/no-multicall-to-self',))]
fn test_no_self_call_invalid_2() {
    let self = 42.try_into().unwrap();
    start_cheat_caller_address_global(self);
    let call1 = Call { to: 1.try_into().unwrap(), selector: 100, calldata: array![].span() };
    let call2 = Call { to: self, selector: 200, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1, call2].span(), self);
}

