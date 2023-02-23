use starknet::get_contract_address;
use starknet::get_caller_address;
use zeroable::Zeroable;
use starknet::ContractAddressZeroable;
use traits::Into;
use starknet::ContractAddressIntoFelt;

const TRANSACTION_VERSION: felt = 1;
const QUERY_VERSION: felt = 340282366920938463463374607431768211457; // 2**128 + TRANSACTION_VERSION

#[inline(always)]
fn assert_only_self() {
    assert(get_contract_address().into() == get_caller_address().into(), 'argent/only-self');
}

#[inline(always)]
fn assert_non_reentrant(signer: felt) {
    assert(get_caller_address().is_zero(), 'argent/no-reentrant-call');
}

#[inline(always)]
fn assert_correct_tx_version(tx_version: felt) {
    let is_valid = tx_version == TRANSACTION_VERSION ^ tx_version == QUERY_VERSION;
    assert(is_valid, 'argent/invalid-tx-version');
}
