use array::ArrayTrait;
use contracts::dummy_syscalls;
use contracts::argent_account::CallArray;

const TRANSACTION_VERSION: felt = 1;
const QUERY_VERSION: felt = 340282366920938463463374607431768211457; // 2**128 + TRANSACTION_VERSION

fn assert_only_self() {
    let self = dummy_syscalls::get_contract_address();
    let caller_address = dummy_syscalls::get_caller_address();
    assert(self == caller_address, 'argent/only-self');
}

fn assert_non_reentrant(signer: felt) {
    let caller_address = dummy_syscalls::get_caller_address();
    assert(caller_address == 0, 'argent/no-reentrant-call');
}

fn assert_correct_tx_version(tx_version: felt) {
    let is_valid = tx_version == TRANSACTION_VERSION ^ tx_version == QUERY_VERSION;
    assert(is_valid, 'argent/invalid-tx-version');
}

fn assert_no_self_call(ref call_array: Array::<CallArray>, self: felt) {
    assert_no_self_call_internal(ref call_array, self, 0_usize);
}

fn assert_no_self_call_internal(ref call_array: Array::<CallArray>, self: felt, index: usize) {
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
    assert_no_self_call_internal(ref call_array, self, index + 1_usize);
    return ();
}
