use argent::common::transaction_version;
use starknet::{contract_address_const, testing::{set_caller_address, set_contract_address}, account::Call};


#[test]
fn assert_correct_invoke_version() {
    transaction_version::assert_correct_invoke_version(1);
    transaction_version::assert_correct_invoke_version(0x100000000000000000000000000000000 + 1);
    transaction_version::assert_correct_invoke_version(3);
    transaction_version::assert_correct_invoke_version(0x100000000000000000000000000000000 + 3);
}


#[test]
#[should_panic(expected: ('argent/invalid-tx-version',))]
fn assert_invoke_version_invalid() {
    transaction_version::assert_correct_invoke_version(2);
}

#[test]
fn assert_correct_declare_version() {
    transaction_version::assert_correct_declare_version(2);
    transaction_version::assert_correct_declare_version(0x100000000000000000000000000000000 + 2);
    transaction_version::assert_correct_declare_version(3);
    transaction_version::assert_correct_declare_version(0x100000000000000000000000000000000 + 3);
}

#[test]
#[should_panic(expected: ('argent/invalid-declare-version',))]
fn assert_declare_version_invalid() {
    transaction_version::assert_correct_declare_version(1);
}
