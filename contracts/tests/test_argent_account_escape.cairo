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

#[test]
#[available_gas(2000000)]
fn trigger_escape_signer() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_signer();
    let escape = ArgentAccount::get_escape();
    assert(
        escape.active_at == DEFAULT_TIMESTAMP.into() + ESCAPE_SECURITY_PERIOD, 'active_at invalid'
    );
    assert(escape.escape_type == ESCAPE_TYPE_SIGNER, 'escape_type invalid');
}

// trigger_escape_guardian
#[test]
#[available_gas(2000000)]
fn trigger_escape_guardian_by_signer() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
    let escape = ArgentAccount::get_escape();
    assert(
        escape.active_at == DEFAULT_TIMESTAMP.into() + ESCAPE_SECURITY_PERIOD, 'active_at invalid'
    );
    assert(escape.escape_type == ESCAPE_TYPE_GUARDIAN, 'escape_type invalid');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn trigger_escape_guardian_without_guardian() {
    initialize_account_without_guardian();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_guardian();
}


// escape_signer
#[test]
#[available_gas(2000000)] // TODO Ongoing
#[should_panic]
fn escape_signer() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_signer();
    set_block_timestamp(DEFAULT_TIMESTAMP + 604800_u64);
    ArgentAccount::escape_signer(42);
    assert_escape_cleared();
    assert(ArgentAccount::get_signer() == 42, 'Signer should now be 42');
}

// escape_guardian

// Cancel escape 

#[test]
#[available_gas(2000000)]
fn cancel_escape() {
    initialize_account();
    ArgentAccount::trigger_escape_signer();
    assert_escape_cleared();
    ArgentAccount::cancel_escape();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at.is_zero(), 'active_at == 0');
    assert(escape.escape_type.is_zero(), 'escape_type == 0');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn cancel_escape_assert_only_self() {
    initialize_account();
    set_caller_address(contract_address_const::<42>());
    ArgentAccount::cancel_escape();
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn cancel_escape_no_escape_set() {
    initialize_account();
    ArgentAccount::trigger_escape_signer();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at != ESCAPE_SECURITY_PERIOD, 'active_at != zero');
    assert(escape.escape_type != ESCAPE_TYPE_GUARDIAN, 'escape_type != zero');
}

// get_escape 

fn get_escape() {
    initialize_account();
    set_block_timestamp(DEFAULT_TIMESTAMP);
    ArgentAccount::trigger_escape_signer();
    let escape = ArgentAccount::get_escape();
    assert(
        escape.active_at == DEFAULT_TIMESTAMP.into() + ESCAPE_SECURITY_PERIOD, '=DEFAULT+SEC_PERIOD'
    );
    assert(escape.escape_type == ESCAPE_TYPE_GUARDIAN, '=ESCAPE_TYPE_GUARDIAN');
}

fn get_escape_signer() {
    initialize_account();
    ArgentAccount::trigger_escape_signer();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, '=ESCAPE_SECURITY_PERIOD');
    assert(escape.escape_type == ESCAPE_TYPE_SIGNER, '=ESCAPE_TYPE_SIGNER');
}

fn get_escape_signer_guardian() {
    initialize_account();
    ArgentAccount::trigger_escape_signer();
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at == ESCAPE_SECURITY_PERIOD, '=ESCAPE_SECURITY_PERIOD');
    assert(escape.escape_type == ESCAPE_TYPE_GUARDIAN, '=ESCAPE_TYPE_GUARDIAN');
}

#[test]
#[available_gas(2000000)]
fn get_escape_unitialized() {
    initialize_account();
    assert(ArgentAccount::get_escape().active_at.is_zero(), 'Unitialized escape should be 0');
}
// TODO Each signer stuff should have an assert_only_self test
// TODO Each signer stuff should have an assert_guardian_set test

// Utils
fn assert_escape_cleared() {
    let escape = ArgentAccount::get_escape();
    assert(escape.active_at != 0, 'active_at != zero');
    assert(escape.escape_type != 0, 'escape_type != zero');
}
