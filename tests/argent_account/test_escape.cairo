use argent::multiowner_account::{argent_account::ArgentAccount, events::EscapeSecurityPeriodChanged};
use argent::recovery::EscapeStatus;
use argent::signer::signer_signature::starknet_signer_from_pubkey;
use crate::{Felt252TryIntoStarknetSigner, ITestArgentAccountDispatcherTrait, initialize_account};
use snforge_std::{
    EventSpyAssertionsTrait, EventSpyTrait, spy_events, start_cheat_block_timestamp_global,
    start_cheat_caller_address_global,
};

#[test]
fn set_escape_security_period() {
    let account = initialize_account();
    let default_escape_security_period = account.get_escape_security_period();
    assert_eq!(default_escape_security_period, 7 * 24 * 60 * 60);

    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::None);

    let mut spy = spy_events();
    account.set_escape_security_period(4200);
    let new_escape_security_period = account.get_escape_security_period();
    assert_eq!(new_escape_security_period, 4200);

    let event = ArgentAccount::Event::EscapeSecurityPeriodChanged(
        EscapeSecurityPeriodChanged { escape_security_period: 4200 },
    );
    spy.assert_emitted(@array![(account.contract_address, event)]);

    assert_eq!(spy.get_events().events.len(), 1);
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn set_escape_security_period_with_not_ready_escape() {
    let account = initialize_account();
    account.trigger_escape_guardian(Option::None);

    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::NotReady);

    account.set_escape_security_period(4200);
}


#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn set_escape_security_period_with_ready_escape() {
    let account = initialize_account();
    account.trigger_escape_guardian(Option::None);

    start_cheat_block_timestamp_global(7 * 24 * 60 * 60);
    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::Ready);

    account.set_escape_security_period(4200);
}

#[test]
fn set_escape_security_period_with_expired_escape() {
    let account = initialize_account();
    account.trigger_escape_guardian(Option::None);

    start_cheat_block_timestamp_global(7 * 24 * 60 * 60 * 2);
    let (escape, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::Expired);
    assert_ne!(escape.ready_at, 0, "Should not be 0");

    account.set_escape_security_period(4200);

    let new_escape_security_period = account.get_escape_security_period();
    assert_eq!(new_escape_security_period, 4200);
    let (new_escape, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::None);
    assert_eq!(new_escape.ready_at, 0);
}

#[test]
fn set_escape_security_period_get_escape_status() {
    let account = initialize_account();
    account.set_escape_security_period(4200);

    let (_, no_escape) = account.get_escape_and_status();
    assert_eq!(no_escape, EscapeStatus::None);

    start_cheat_block_timestamp_global(100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));

    start_cheat_block_timestamp_global(100 + 4200 - 1);
    let (_, not_ready) = account.get_escape_and_status();
    assert_eq!(not_ready, EscapeStatus::NotReady);

    start_cheat_block_timestamp_global(100 + 4200);
    let (_, ready_early) = account.get_escape_and_status();
    assert_eq!(ready_early, EscapeStatus::Ready);

    start_cheat_block_timestamp_global(100 + (4200 * 2) - 1);
    let (_, ready_late) = account.get_escape_and_status();
    assert_eq!(ready_late, EscapeStatus::Ready);

    start_cheat_block_timestamp_global(100 + (4200 * 2));
    let (_, expired) = account.get_escape_and_status();
    assert_eq!(expired, EscapeStatus::Expired);
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn set_escape_security_period_outside() {
    let account = initialize_account();
    start_cheat_caller_address_global('another caller'.try_into().unwrap());
    account.set_escape_security_period(4200);
}

#[test]
#[should_panic(expected: ('argent/invalid-security-period',))]
fn set_escape_security_period__to_zero() {
    let account = initialize_account();
    account.set_escape_security_period(0);
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn set_escape_security_period_escape_too_early() {
    let account = initialize_account();
    account.set_escape_security_period(4200);
    start_cheat_block_timestamp_global(100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    start_cheat_block_timestamp_global(100 + 4200 - 1);
    account.escape_owner();
}

#[test]
fn set_escape_security_period_escape_escape() {
    let account = initialize_account();
    account.set_escape_security_period(4200);
    start_cheat_block_timestamp_global(100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    start_cheat_block_timestamp_global(100 + 4200);
    account.escape_owner();
    let new_owner = account.get_owner();
    assert_eq!(new_owner, 12);
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn set_escape_security_period_escape_escape_too_late() {
    let account = initialize_account();
    account.set_escape_security_period(4200);
    start_cheat_block_timestamp_global(100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    start_cheat_block_timestamp_global(100 + (4200 * 2));
    account.escape_owner();
}


#[test]
fn escape_owner_default() {
    let account = initialize_account();
    start_cheat_block_timestamp_global(100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    start_cheat_block_timestamp_global(100 + 7 * 24 * 60 * 60);
    account.escape_owner();
    let new_owner = account.get_owner();
    assert_eq!(new_owner, 12);
}
