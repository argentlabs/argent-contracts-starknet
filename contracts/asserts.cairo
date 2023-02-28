use traits::Into;
use array::ArrayTrait;
use zeroable::Zeroable;
use starknet::get_contract_address;
use starknet::get_caller_address;
use starknet::ContractAddressZeroable;
use starknet::ContractAddressIntoFelt;

use contracts::argent_account::ArgentAccount::Call;

const TRANSACTION_VERSION: felt = 1;
const QUERY_VERSION: felt = 340282366920938463463374607431768211457; // 2**128 + TRANSACTION_VERSION

fn assert_only_self() {
    assert(get_contract_address().into() == get_caller_address().into(), 'argent/only-self');
}

fn assert_non_reentrant(signer: felt) {
    assert(get_caller_address().is_zero(), 'argent/no-reentrant-call');
}

fn assert_correct_tx_version(tx_version: felt) {
    let is_valid = tx_version == TRANSACTION_VERSION ^ tx_version == QUERY_VERSION;
    assert(is_valid, 'argent/invalid-tx-version');
}

fn assert_no_self_call(calls: @Array::<Call>, self: ContractAddress) {
    assert_no_self_call_internal(calls, self, 0_usize);
}

fn assert_no_self_call_internal(calls: @Array::<Call>, self: ContractAddress, index: usize) {
    match try_fetch_gas() {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut data = ArrayTrait::new();
            data.append('Out of gas');
            panic(data);
        },
    }
    if index == calls.len() {
        return ();
    }
    let to = *calls.at(index).to;
    assert(to.into() != self.into(), 'argent/no-multicall-to-self');
    assert_no_self_call_internal(calls, self, index + 1_usize);
}
