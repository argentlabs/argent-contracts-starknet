use argent::utils::asserts;
use core::traits::TryInto;
use snforge_std::{CheatSpan, cheat_caller_address, test_address};
use starknet::account::Call;
use starknet::testing::{set_caller_address, set_contract_address};
use starknet::{ContractAddress, get_contract_address};

#[test]
fn test_assert_only_self() {
    cheat_caller_address(get_contract_address(), test_address(), CheatSpan::Indefinite(()));
    asserts::assert_only_self();
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_assert_only_self_panic() {
    let address: ContractAddress = 42.try_into().unwrap();
    cheat_caller_address(get_contract_address(), address, CheatSpan::Indefinite(()));
    asserts::assert_only_self();
}

#[test]
fn test_no_self_call_empty() {
    let self_address: ContractAddress = 42.try_into().unwrap();
    cheat_caller_address(get_contract_address(), self_address, CheatSpan::Indefinite(()));
    let calls = array![];
    asserts::assert_no_self_call(calls.span(), self_address);
}

#[test]
fn test_no_self_call_1() {
    let self_address: ContractAddress = 42.try_into().unwrap();
    let other_address: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(get_contract_address(), self_address, CheatSpan::Indefinite(()));
    let call1 = Call { to: other_address, selector: 100, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1].span(), self_address);
}

#[test]
fn test_no_self_call_2() {
    let self_address: ContractAddress = 42.try_into().unwrap();
    let address1: ContractAddress = 2.try_into().unwrap();
    let address2: ContractAddress = 3.try_into().unwrap();
    cheat_caller_address(get_contract_address(), self_address, CheatSpan::Indefinite(()));
    let call1 = Call { to: address1, selector: 100, calldata: array![].span() };
    let call2 = Call { to: address2, selector: 200, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1, call2].span(), self_address);
}

#[test]
#[should_panic(expected: ('argent/no-multicall-to-self',))]
fn test_no_self_call_invalid() {
    let self_address: ContractAddress = 42.try_into().unwrap();
    cheat_caller_address(get_contract_address(), self_address, CheatSpan::Indefinite(()));
    let call = Call { to: self_address, selector: 100, calldata: array![].span() };
    asserts::assert_no_self_call(array![call].span(), self_address);
}

#[test]
#[should_panic(expected: ('argent/no-multicall-to-self',))]
fn test_no_self_call_invalid_2() {
    let self_address: ContractAddress = 42.try_into().unwrap();
    let other_address: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(get_contract_address(), self_address, CheatSpan::Indefinite(()));
    let call1 = Call { to: other_address, selector: 100, calldata: array![].span() };
    let call2 = Call { to: self_address, selector: 200, calldata: array![].span() };
    asserts::assert_no_self_call(array![call1, call2].span(), self_address);
}

