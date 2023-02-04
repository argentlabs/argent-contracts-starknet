use array::ArrayTrait;
use contracts::dummy_syscalls;
use contracts::asserts;
use contracts::argent_account::CallArray;
use contracts::argent_account::ArrayCallArrayDrop;

#[test]
fn test_assert_only_self() {
    asserts::assert_only_self();
}

#[test]
fn assert_correct_tx_version_test() {
    // for now valid tx_version == 1 & 2
    let tx_version = 1;
    asserts::assert_correct_tx_version(tx_version);
}

#[test]
#[should_panic(expected = 'argent: invalid tx version')]
fn assert_correct_tx_version_invalidtx_test() {
    // for now valid tx_version == 1 & 2
    let tx_version = 4;
    asserts::assert_correct_tx_version(tx_version);
    let tx_version = 4;
    asserts::assert_correct_tx_version(tx_version);
}

#[test]
#[available_gas(2000000)]
fn test_no_self_call() {
    let self = dummy_syscalls::get_contract_address();
    let mut call_array = ArrayTrait::new();
    asserts::assert_no_self_call(ref call_array, self);
    let mut call_array = ArrayTrait::new();
    call_array.append(CallArray { to: 0, selector: 100, data_offset: 0, data_len: 2 });
    asserts::assert_no_self_call(ref call_array, self);
    let mut call_array = ArrayTrait::new();
    call_array.append(CallArray { to: 1, selector: 100, data_offset: 0, data_len: 2 });
    call_array.append(CallArray { to: 2, selector: 200, data_offset: 2, data_len: 3 });
    asserts::assert_no_self_call(ref call_array, self);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = 'argent: no self call')]
fn test_no_self_call_invalid() {
    let self = dummy_syscalls::get_contract_address();
    let mut call_array = ArrayTrait::new();
    call_array.append(CallArray { to: self, selector: 100, data_offset: 0, data_len: 2 });
    asserts::assert_no_self_call(ref call_array, self);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = 'argent: no self call')]
fn test_no_self_call_invalid_2() {
    let self = dummy_syscalls::get_contract_address();
    let mut call_array = ArrayTrait::new();
    call_array.append(CallArray { to: 1, selector: 100, data_offset: 0, data_len: 2 });
    call_array.append(CallArray { to: self, selector: 200, data_offset: 2, data_len: 3 });
    asserts::assert_no_self_call(ref call_array, self);
}
