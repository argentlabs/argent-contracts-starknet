use contracts::ArgentAccount;
use contracts::ArgentAccount::Escape;
use zeroable::Zeroable;
use starknet::contract_address_const;
use traits::Into;
use starknet_testing::set_block_timestamp;
use starknet_testing::set_caller_address;

use contracts::tests::initialize_account;
use contracts::tests::initialize_account_without_guardian;

const DEFAULT_TIMESTAMP: u64 = 42_u64;
const ESCAPE_SECURITY_PERIOD: felt = 604800; // 7 * 24 * 60 * 60;  // 7 days
const ESCAPE_TYPE_GUARDIAN: felt = 1;
const ESCAPE_TYPE_SIGNER: felt = 2;

// trigger_escape_signer

// trigger_escape_guardian

// escape_signer
// TODO Every branch tested
#[test]
#[available_gas(2000000)]
fn escape_signer() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_signer();
    set_block_timestamp(DEFAULT_TIMESTAMP + 604800_u64);
    ArgentAccount::escape_signer(42);
    assert(ArgentAccount::get_signer() == 42, 'Signer == 42');
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
fn escape_signer_after_timeout() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_signer();
    set_block_timestamp(DEFAULT_TIMESTAMP + 604801_u64);
    ArgentAccount::escape_signer(42);
    assert(ArgentAccount::get_signer() == 42, 'Signer == 42');
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/only-self', ))]
fn escape_signer_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::escape_signer(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/guardian-required', ))]
fn escape_signer_no_guardian_set() {
    initialize_account_without_guardian();
    ArgentAccount::escape_signer(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/not-escaping', ))]
fn escape_signer_not_escaping() {
    initialize_account();
    set_block_timestamp(604800_u64);
    ArgentAccount::escape_signer(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/escape-not-active', ))]
fn escape_signer_before_timeout() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_signer();
    set_block_timestamp(DEFAULT_TIMESTAMP + 604799_u64);
    ArgentAccount::escape_signer(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/escape-type-invalid', ))]
fn escape_signer_wrong_escape_type() {
    initialize_account();
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(604800_u64);
    ArgentAccount::escape_signer(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/new-signer-zero', ))]
fn escape_signer_new_signer_zero() {
    initialize_account();
    ArgentAccount::trigger_escape_signer();
    set_block_timestamp(604800_u64);
    ArgentAccount::escape_signer(0);
}

// escape_guardian
// TODO Every branch tested

#[test]
#[available_gas(2000000)]
fn escape_guardian() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(DEFAULT_TIMESTAMP + 604800_u64);
    ArgentAccount::escape_guardian(42);
    assert(ArgentAccount::get_guardian() == 42, 'Guardian == 42');
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
fn escape_guardian_after_timeout() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(DEFAULT_TIMESTAMP + 604801_u64);
    ArgentAccount::escape_guardian(42);
    assert(ArgentAccount::get_guardian() == 42, 'Guardian == 42');
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/only-self', ))]
fn escape_guardian_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/guardian-required', ))]
fn escape_guardian_no_guardian_set() {
    initialize_account_without_guardian();
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/not-escaping', ))]
fn escape_guardian_not_escaping() {
    initialize_account();
    set_block_timestamp(604800_u64);
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/escape-not-active', ))]
fn escape_guardian_before_timeout() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(DEFAULT_TIMESTAMP + 604799_u64);
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/escape-type-invalid', ))]
fn escape_guardian_wrong_escape_type() {
    initialize_account();
    ArgentAccount::trigger_escape_signer();
    set_block_timestamp(604800_u64);
    ArgentAccount::escape_guardian(42);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/new-guardian-zero', ))]
fn escape_guardian_new_guardian_zero() {
    initialize_account();
    ArgentAccount::trigger_escape_guardian();
    set_block_timestamp(604800_u64);
    ArgentAccount::escape_guardian(0);
}

// cancel_escape
// TODO Every branch tested

#[test]
#[available_gas(2000000)]
fn cancel_escape() {
    initialize_account();
    ArgentAccount::trigger_escape_signer();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at != 0, 'active_at != zero');
    assert(escape.escape_type != 0, 'escape_type != zero');
    ArgentAccount::cancel_escape();
    assert_escape_cleared();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/only-self', ))]
fn cancel_escape_assert_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::cancel_escape();
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = ('argent/no-active-escape', ))]
fn cancel_escape_no_escape_set() {
    initialize_account();
    ArgentAccount::cancel_escape();
}

// get_escape 
// TODO Every branch tested

#[test]
#[available_gas(2000000)]
fn get_escape() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_signer();
    let escape = ArgentAccount::get_escape();
    assert(
        escape.active_at == DEFAULT_TIMESTAMP.into() + ESCAPE_SECURITY_PERIOD, '=DEFAULT+SEC_PERIOD'
    );
    assert(escape.escape_type == ESCAPE_TYPE_SIGNER, '=ESCAPE_TYPE_GUARDIAN');
}

#[test]
#[available_gas(2000000)]
fn get_escape_signer() {
    initialize_account();
    ArgentAccount::trigger_escape_signer();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, '=ESCAPE_SECURITY_PERIOD');
    assert(escape.escape_type == ESCAPE_TYPE_SIGNER, '=ESCAPE_TYPE_SIGNER');
}

#[test]
#[available_gas(2000000)]
fn get_escape_signer_guardian() {
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
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at.is_zero(), 'active_at is zero');
    assert(escape.escape_type.is_zero(), 'escape_type is zero');
}

fn assert_escape_cleared() {
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at.is_zero(), 'active_at == 0');
    assert(escape.escape_type.is_zero(), 'escape_type == 0');
}
