use contracts::ArgentAccount;
use contracts::dummy_syscalls;
use debug::print_felt;

<<<<<<< HEAD
=======

const ESCAPE_SECURITY_PERIOD: felt = 604800; // 7 days
const ESCAPE_TYPE_GUARDIAN: felt = 1;
const ESCAPE_TYPE_SIGNER: felt = 2;
const INITIALIZED_SIGNER: felt = 1;
const INITIALIZED_GUARDIAN: felt = 2;

#[test]
#[available_gas(2000000)]
fn valid_trigger_escape_signer() {
<<<<<<< HEAD
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::triggerEscapeSigner();

    let escape_active_at = ArgentAccount::get_escape_active_at();
    let block_timestamp = dummy_syscalls::get_block_timestamp();
    assert(
        escape_active_at == block_timestamp + ArgentAccount::ESCAPE_SECURITY_PERIOD,
        'escape activation set to wrong timestamp'
    );

    let escape_type = ArgentAccount::get_escape_type();
    assert(escape_type == ArgentAccount::ESCAPE_TYPE_SIGNER, 'wrong escape type');
}

#[test]
#[available_gas(2000000)]
fn trigger_escape_signer_escape_already_active() {
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::triggerEscapeSigner();
    ArgentAccount::triggerEscapeSigner();
}

#[test]
#[available_gas(2000000)]
fn trigger_escape_signer_escape_already_active() {
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::trigger_escape_signer();
    ArgentAccount::trigger_escape_signer();
}


#[test]
#[available_gas(2000000)]
<<<<<<< HEAD
#[should_panic(expected = 'argent: cannot override escape')]
fn trigger_escape_signer_escape_already_active() {
<<<<<<< HEAD
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
=======
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0); 
>>>>>>> 822aa45 (finished testing escaping signer)
    ArgentAccount::trigger_escape_signer();
    ArgentAccount::trigger_escape_signer();
}

#[test]
#[available_gas(2000000)]
=======
>>>>>>> bc61f76 (changed guardian asserts to be inline wihtout additional var, fixed cannot override escape assert in escape signer)
fn escape_signer() {
    let new_signer = 5;
<<<<<<< HEAD
    // 7 days + current timestamp + 1 block
    let future_timestamp = dummy_syscalls::get_block_timestamp()
        + ArgentAccount::ESCAPE_SECURITY_PERIOD
        + 1;
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::triggerEscapeSigner();
    ArgentAccount::escapeSigner(new_signer, future_timestamp);

    // check escape cleared
    let escape_active_at = ArgentAccount::get_escape_active_at();
    let escape_type = ArgentAccount::get_escape_type();
<<<<<<< HEAD
    assert(escape_active_at == 0 & escape_type == 0, 'escape not cleared');
=======
    assert(escape_active_at == 0 & escape_type == 0 , 'escape not cleared');
>>>>>>> 822aa45 (finished testing escaping signer)

    // check new signer
    let changed_signer = ArgentAccount::get_signer();
    assert(changed_signer == new_signer, 'signer was not changed to the new one')
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = 'argent: not escaping')]
fn escape_signer_no_active_escape() {
    let new_signer = 5;
    // 7 days + current timestamp + 1 block
    let future_timestamp = dummy_syscalls::get_block_timestamp()
        + ArgentAccount::ESCAPE_SECURITY_PERIOD
        + 1;
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::escapeSigner(new_signer, future_timestamp);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = 'argent: escape not active')]
fn escape_signer_not_active_yet() {
    let new_signer = 5;
    // 7 days + current timestamp 
    let future_timestamp = dummy_syscalls::get_block_timestamp()
        + ArgentAccount::ESCAPE_SECURITY_PERIOD;
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::triggerEscapeSigner();
    ArgentAccount::escapeSigner(new_signer, future_timestamp);

    let signer = ArgentAccount::get_signer();
    assert(signer == INITIALIZED_SIGNER, 'signer was mistakenly changed to the new one')
}

#[test]
#[available_gas(2000000)]
fn cancel_escape() {
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::triggerEscapeSigner();
    ArgentAccount::cancelEscape();

    let signer = ArgentAccount::get_signer();
    assert(signer == INITIALIZED_SIGNER, 'signer was mistakenly changed to the new one')

    // check escape cleared
    let escape_active_at = ArgentAccount::get_escape_active_at();
    let escape_type = ArgentAccount::get_escape_type();
    assert(escape_active_at == 0 & escape_type == 0, 'escape not cleared');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected = 'argent: escape not active')]
fn cancel_no_active_escape() {
    ArgentAccount::initialize(INITIALIZED_SIGNER, INITIALIZED_GUARDIAN, 0);
    ArgentAccount::cancelEscape();
}

