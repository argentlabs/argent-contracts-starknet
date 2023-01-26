use contracts::ArgentAccount;
use contracts::dummy_syscalls;

const INITIALIZED_SIGNER: felt = 1;
const INITIALIZED_GUARDIAN: felt = 2;

#[test]
#[available_gas(20000)]
fn valid_trigger_escape_signer() {
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::trigger_escape_signer();

    let escape_active_at = ArgentAccount::get_escape_active_at();
    let escape_type = ArgentAccount::get_escape_type();
    let block_timestamp = dummy_syscalls::get_block_timestamp();
    assert(
        escape_active_at == block_timestamp + ArgentAccount::ESCAPE_SECURITY_PERIOD,
        'escape activation set to wrong timestamp'
    );
    assert(escape_type == ArgentAccount::ESCAPE_TYPE_SIGNER, 'wrong escape type');
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: cannot override escape')]
fn trigger_escape_signer_escape_already_active() {
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::trigger_escape_signer();
    ArgentAccount::trigger_escape_signer();
}

#[test]
#[available_gas(20000)]
fn escape_signer() {
    let new_signer = 5;
    // 7 days + current timestamp + 1 block
    let future_timestamp = dummy_syscalls::get_block_timestamp()
        + ArgentAccount::ESCAPE_SECURITY_PERIOD
        + 1;
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::trigger_escape_signer();
    ArgentAccount::escape_signer(new_signer, future_timestamp);

    // check escape cleared
    let escape_active_at = ArgentAccount::get_escape_active_at();
    let escape_type = ArgentAccount::get_escape_type();
    assert(escape_active_at == 0 & escape_type == 0, 'escape not cleared');

    // check new signer
    let changed_signer = ArgentAccount::get_signer();
    assert(changed_signer == new_signer, 'signer was not changed to the new one')
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: not escaping')]
fn escape_signer_no_active_escape() {
    let new_signer = 5;
    // 7 days + current timestamp + 1 block
    let future_timestamp = dummy_syscalls::get_block_timestamp()
        + ArgentAccount::ESCAPE_SECURITY_PERIOD
        + 1;
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::escape_signer(new_signer, future_timestamp);
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: escape not active')]
fn escape_signer_not_active_yet() {
    let new_signer = 5;
    // 7 days + current timestamp 
    let future_timestamp = dummy_syscalls::get_block_timestamp()
        + ArgentAccount::ESCAPE_SECURITY_PERIOD;
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::trigger_escape_signer();
    ArgentAccount::escape_signer(new_signer, future_timestamp);

    let signer = ArgentAccount::get_signer();
    assert(signer == INITIALIZED_SIGNER, 'signer was mistakenly changed to the new one')
}

#[test]
#[available_gas(20000)]
fn cancel_escape() {
    let new_signer = 5;
    let future_timestamp = dummy_syscalls::get_block_timestamp()
        + ArgentAccount::ESCAPE_SECURITY_PERIOD
        + 1; // 7 days + current timestamp + 1 block
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::trigger_escape_signer();
    ArgentAccount::cancel_escape();

    let signer = ArgentAccount::get_signer();
    assert(signer == INITIALIZED_SIGNER, 'signer was mistakenly changed to the new one')

    // check escape cleared
    let escape_active_at = ArgentAccount::get_escape_active_at();
    let escape_type = ArgentAccount::get_escape_type();
    assert(escape_active_at == 0 & escape_type == 0, 'escape not cleared');
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: escape not active')]
fn cancel_no_active_escape() {
    let new_signer = 5;
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::cancel_escape();
}

