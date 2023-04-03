use array::ArrayTrait;
use array::SpanTrait;
use traits::Into;
use zeroable::Zeroable;

use starknet::get_contract_address;
use starknet::get_caller_address;
use starknet::ContractAddress;
use starknet::ContractAddressZeroable;
use starknet::ContractAddressIntoFelt252;

use lib::Call;
use lib::check_enough_gas;

const TRANSACTION_VERSION: felt252 = 1;
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
    // TODO Once we have || => can be one liner
    if tx_version != TRANSACTION_VERSION {
        assert(tx_version == QUERY_VERSION, 'argent/invalid-tx-version');
    }
}

fn assert_no_self_call(mut calls: Span::<Call>, self: ContractAddress) {
    check_enough_gas();

    match calls.pop_front() {
        Option::Some(call) => {
            assert((*call.to).into() != self.into(), 'argent/no-multicall-to-self');
            assert_no_self_call(calls, self);
        },
        Option::None(_) => (),
    }
}
