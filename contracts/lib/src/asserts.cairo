use array::{ArrayTrait, SpanTrait};
use traits::Into;
use zeroable::Zeroable;

use starknet::{
    get_contract_address, get_caller_address, ContractAddress, ContractAddressIntoFelt252
};

use lib::Call;

const TRANSACTION_VERSION: felt252 = 1;
const CASM_DECLARE_VERSION: felt252 = 1;
const SIERRA_DECLARE_VERSION: felt252 = 2;
const QUERY_VERSION: felt252 =
    340282366920938463463374607431768211457; // 2**128 + TRANSACTION_VERSION

#[inline(always)]
fn assert_only_self() {
    assert(get_contract_address().into() == get_caller_address().into(), 'argent/only-self');
}

#[inline(always)]
fn assert_non_reentrant() {
    assert(get_caller_address().is_zero(), 'argent/no-reentrant-call');
}

#[inline(always)]
fn assert_correct_tx_version(tx_version: felt252) {
    if tx_version != TRANSACTION_VERSION {
        assert(tx_version == QUERY_VERSION, 'argent/invalid-tx-version');
    }
}

#[inline(always)]
fn assert_correct_declare_version(tx_version: felt252) {
    if tx_version == SIERRA_DECLARE_VERSION {
        return ();
    }
    if tx_version == CASM_DECLARE_VERSION {
        return ();
    }
    assert(tx_version == QUERY_VERSION, 'argent/invalid-contract-version');
}

fn assert_no_self_call(mut calls: Span::<Call>, self: ContractAddress) {
    match calls.pop_front() {
        Option::Some(call) => {
            assert((*call.to).into() != self.into(), 'argent/no-multicall-to-self');
            assert_no_self_call(calls, self);
        },
        Option::None(_) => (),
    }
}
