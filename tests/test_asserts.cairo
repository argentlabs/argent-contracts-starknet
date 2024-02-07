use argent::utils::asserts;
use starknet::{contract_address_const, testing::{set_caller_address, set_contract_address}, account::Call};

#[test]
#[available_gas(2000000)]
fn test_assert_only_self() {
    set_caller_address(contract_address_const::<42>());
    set_contract_address(contract_address_const::<42>());
    asserts::assert_only_self();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self',))]
fn test_assert_only_self_panic() {
    set_caller_address(contract_address_const::<42>());
    set_contract_address(contract_address_const::<69>());
    asserts::assert_only_self();
}

#[test]
#[available_gas(2000000)]
fn test_no_self_call_empty() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let calls = array![];
    asserts::assert_no_self_call(calls.span(), self);
}

#[test]
#[available_gas(2000000)]
fn test_no_self_call_1() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let call1 = Call { to: contract_address_const::<1>(), selector: 100, calldata: array![] };
    asserts::assert_no_self_call(array![call1].span(), self);
}

#[test]
#[available_gas(2000000)]
fn test_no_self_call_2() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let call1 = Call { to: contract_address_const::<2>(), selector: 100, calldata: array![] };
    let call2 = Call { to: contract_address_const::<3>(), selector: 200, calldata: array![] };
    asserts::assert_no_self_call(array![call1, call2].span(), self);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/no-multicall-to-self',))]
fn test_no_self_call_invalid() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let call = Call { to: self, selector: 100, calldata: array![] };
    asserts::assert_no_self_call(array![call].span(), self);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/no-multicall-to-self',))]
fn test_no_self_call_invalid_2() {
    let self = contract_address_const::<42>();
    set_caller_address(self);
    let call1 = Call { to: contract_address_const::<1>(), selector: 100, calldata: array![] };
    let call2 = Call { to: self, selector: 200, calldata: array![] };
    asserts::assert_no_self_call(array![call1, call2].span(), self);
}
