use zeroable::Zeroable;
use starknet::contract_address_const;
use starknet::testing::set_block_timestamp;
use starknet::testing::set_caller_address;

use account::ArgentAccount;
use account::tests::initialize_account;
use account::tests::initialize_account_without_guardian;

const DEFAULT_TIMESTAMP: u64 = 42;
const ESCAPE_SECURITY_PERIOD: u64 = 604800; // 7 * 24 * 60 * 60;  // 7 days
const ESCAPE_TYPE_GUARDIAN: felt252 = 1;
const ESCAPE_TYPE_OWNER: felt252 = 2;

// trigger_escape_owner

#[test]
#[available_gas(2000000)]
fn trigger_escape_owner() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_owner();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD, 'active_at invalid');
    assert(escape.escape_type == ESCAPE_TYPE_OWNER, 'escape_type invalid');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', ))]
fn trigger_escape_owner_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::trigger_escape_owner();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/guardian-required', ))]
fn trigger_escape_owner_no_guardian_set() {
    initialize_account_without_guardian();
    ArgentAccount::trigger_escape_owner();
}

#[test]
#[available_gas(2000000)]
fn trigger_escape_owner_twice() {
    initialize_account();
    ArgentAccount::trigger_escape_owner();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, 'active_at 1 invalid');
    assert(escape.escape_type == ESCAPE_TYPE_OWNER, 'escape_type 1 invalid');

    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_owner();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD, 'active_at 2 invalid');
    assert(escape.escape_type == ESCAPE_TYPE_OWNER, 'escape_type 2 invalid');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/cannot-override-escape', ))]
fn trigger_escape_owner_with_guardian_escaped() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    ArgentAccount::trigger_escape_owner();
}

// trigger_escape_guardian

#[test]
#[available_gas(2000000)]
fn trigger_escape_guardian() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD, 'active_at invalid');
    assert(escape.escape_type == ESCAPE_TYPE_GUARDIAN, 'escape_type invalid');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', ))]
fn trigger_escape_guardian_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::trigger_escape_guardian();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/guardian-required', ))]
fn trigger_escape_guardian_no_guardian_set() {
    initialize_account_without_guardian();
    ArgentAccount::trigger_escape_guardian();
}

#[test]
#[available_gas(2000000)]
fn trigger_escape_guardian_twice() {
    initialize_account();
    ArgentAccount::trigger_escape_guardian();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, 'active_at 1 invalid');
    assert(escape.escape_type == ESCAPE_TYPE_GUARDIAN, 'escape_type 1 invalid');

    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD, 'active_at 2 invalid');
    assert(escape.escape_type == ESCAPE_TYPE_GUARDIAN, 'escape_type 2 invalid');
}

#[test]
#[available_gas(2000000)]
fn trigger_escape_guardian_with_owner_escaped() {
    initialize_account();
    ArgentAccount::trigger_escape_owner();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, 'active_at 1 invalid');
    assert(escape.escape_type == ESCAPE_TYPE_OWNER, 'escape_type 1 invalid');

    ArgentAccount::trigger_escape_guardian();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, 'active_at 2 invalid');
    assert(escape.escape_type == ESCAPE_TYPE_GUARDIAN, 'escape_type 2 invalid');
}

// escape_owner

#[test]
#[available_gas(2000000)]
fn escape_owner() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_owner();
    set_block_timestamp(DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD + 1);
    ArgentAccount::escape_owner(42);
    assert(ArgentAccount::get_owner() == 42, 'Owner == 42');
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
fn escape_owner_at_security_period() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_owner();
    set_block_timestamp(DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD);
    ArgentAccount::escape_owner(42);
    assert(ArgentAccount::get_owner() == 42, 'Owner == 42');
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', ))]
fn escape_owner_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::escape_owner(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/guardian-required', ))]
fn escape_owner_no_guardian_set() {
    initialize_account_without_guardian();
    ArgentAccount::escape_owner(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/not-escaping', ))]
fn escape_owner_not_escaping() {
    initialize_account();
    set_block_timestamp(ESCAPE_SECURITY_PERIOD);
    ArgentAccount::escape_owner(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/inactive-escape', ))]
fn escape_owner_before_timeout() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_owner();
    set_block_timestamp(DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD - 1);
    ArgentAccount::escape_owner(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-escape-type', ))]
fn escape_owner_wrong_escape_type() {
    initialize_account();
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(ESCAPE_SECURITY_PERIOD);
    ArgentAccount::escape_owner(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/null-owner', ))]
fn escape_owner_new_owner_null() {
    initialize_account();
    ArgentAccount::trigger_escape_owner();
    set_block_timestamp(ESCAPE_SECURITY_PERIOD);
    ArgentAccount::escape_owner(0);
}

// escape_guardian

#[test]
#[available_gas(2000000)]
fn escape_guardian() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD + 1);
    ArgentAccount::escape_guardian(42);
    assert(ArgentAccount::get_guardian() == 42, 'Guardian == 42');
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
fn escape_guardian_at_security_period() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD);
    ArgentAccount::escape_guardian(42);
    assert(ArgentAccount::get_guardian() == 42, 'Guardian == 42');
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', ))]
fn escape_guardian_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/guardian-required', ))]
fn escape_guardian_no_guardian_set() {
    initialize_account_without_guardian();
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/not-escaping', ))]
fn escape_guardian_not_escaping() {
    initialize_account();
    set_block_timestamp(ESCAPE_SECURITY_PERIOD);
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/inactive-escape', ))]
fn escape_guardian_before_timeout() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD - 1);
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/invalid-escape-type', ))]
fn escape_guardian_wrong_escape_type() {
    initialize_account();
    ArgentAccount::trigger_escape_owner();
    set_block_timestamp(ESCAPE_SECURITY_PERIOD);
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/null-guardian', ))]
fn escape_guardian_new_guardian_null() {
    initialize_account();
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(ESCAPE_SECURITY_PERIOD);
    ArgentAccount::escape_guardian(0);
}

// cancel_escape

#[test]
#[available_gas(2000000)]
fn cancel_escape() {
    initialize_account();
    ArgentAccount::trigger_escape_owner();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at != 0, 'active_at != zero');
    assert(escape.escape_type != 0, 'escape_type != zero');
    ArgentAccount::cancel_escape();
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/only-self', ))]
fn cancel_escape_assert_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::cancel_escape();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('argent/no-active-escape', ))]
fn cancel_escape_no_escape_set() {
    initialize_account();
    ArgentAccount::cancel_escape();
}

// get_escape 

#[test]
#[available_gas(2000000)]
fn get_escape() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_owner();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD, '=DEFAULT+SEC_PERIOD');
    assert(escape.escape_type == ESCAPE_TYPE_OWNER, '=ESCAPE_TYPE_GUARDIAN');
}

#[test]
#[available_gas(2000000)]
fn get_escape_owner() {
    initialize_account();
    ArgentAccount::trigger_escape_owner();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, '=ESCAPE_SECURITY_PERIOD');
    assert(escape.escape_type == ESCAPE_TYPE_OWNER, '=ESCAPE_TYPE_OWNER');
}

#[test]
#[available_gas(2000000)]
fn get_escape_owner_guardian() {
    initialize_account();
    ArgentAccount::trigger_escape_guardian();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, '=ESCAPE_SECURITY_PERIOD');
    assert(escape.escape_type == ESCAPE_TYPE_GUARDIAN, '=ESCAPE_TYPE_GUARDIAN');
}

#[test]
#[available_gas(2000000)]
fn get_escape_unitialized() {
    initialize_account();
    assert_escape_cleared();
}

fn assert_escape_cleared() {
    let escape = ArgentAccount::get_escape();
    // TODO Back to is_zero when the trait is possible on u64
    assert(escape.active_at == 0, 'active_at == 0');
    assert(escape.escape_type.is_zero(), 'escape_type == 0');
}
// __execute__
// #[test]
// #[available_gas(2000000)]
// fn execute() {
//     let mut arr = ArrayTrait::<Call>::new();
//     arr.append(create_simple_call());
//     arr.append(create_simple_call_with_data(43));
//     let retdata = __execute__(arr);
//     assert(retdata.len() == 2, '2');
//     assert(*retdata[0] == 42, '42');
//     assert(*retdata[1] == 43, '43');
// }

// TODO can't mock tx_version atm so dummy test
// #[test]
// #[available_gas(2000000)]
// // #[should_panic(expected: ('argent/only-self', ))]
// fn execute_assert_correct_tx_version() {
//     initialize_account();
//     set_tx_version(1);
//     __execute__(ArrayTrait::new());
// }

// #[test]
// #[available_gas(2000000)]
// #[should_panic(expected: ('argent/no-reentrant-call', ))]
// fn execute_assert_non_reentrant() {
//     initialize_account();
//     set_caller_address(contract_address_const::<42>());
//     __execute__(ArrayTrait::new());
// }


