use starknet::get_contract_address;
use starknet::get_caller_address;
use zeroable::Zeroable;
use starknet::ContractAddressZeroable;
use traits::Into;
use starknet::ContractAddressIntoFelt;
use array::ArrayTrait;
use contracts::argent_account::CallArray;

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

fn assert_no_self_call(ref call_array: Array::<CallArray>, self: felt, index: usize) {
    match get_gas() {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut data = ArrayTrait::new();
            data.append('Out of gas');
            panic(data);
        },
    }

    if index == call_array.len() {
        return ();
    }
    assert(call_array.at(index).to != self, 'argent: no self call');
    assert_no_self_call(ref call_array, self, index + 1_usize);
    return ();
}
