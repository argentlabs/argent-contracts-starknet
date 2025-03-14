use argent::presets::argent_account::ArgentAccount;
use argent::recovery::interface::EscapeStatus;
use argent::signer::signer_signature::starknet_signer_from_pubkey;
use snforge_std::{
    CheatSpan, EventSpy, EventSpyAssertionsTrait, EventSpyTrait, cheat_block_timestamp, cheat_caller_address,
    spy_events,
};
use super::setup::account_test_setup::{ITestArgentAccountDispatcherTrait, initialize_account};

#[test]
fn set_escape_security_period() {
    let account = initialize_account();
    let default_escape_security_period = account.get_escape_security_period();
    assert_eq!(default_escape_security_period, 7 * 24 * 60 * 60, "Default value incorrect");

    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::None, "Should be EscapeStatus::None");

    let mut spy = spy_events();
    account.set_escape_security_period(4200);
    let new_escape_security_period = account.get_escape_security_period();
    assert_eq!(new_escape_security_period, 4200, "New value incorrect");

    let event = ArgentAccount::Event::EscapeSecurityPeriodChanged(
        ArgentAccount::EscapeSecurityPeriodChanged { escape_security_period: 4200 },
    );
    spy.assert_emitted(@array![(account.contract_address, event)]);
    let events = spy.get_events();
    assert_eq!(events.events.len(), 0, "excess events");
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn set_escape_security_period_with_not_ready_escape() {
    let account = initialize_account();
    account.trigger_escape_guardian(Option::None);

    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::NotReady, "Should be EscapeStatus::NotReady");

    account.set_escape_security_period(4200);
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn set_escape_security_period_with_ready_escape() {
    let account = initialize_account();
    account.trigger_escape_guardian(Option::None);

    cheat_block_timestamp(account.contract_address, 7 * 24 * 60 * 60, CheatSpan::Indefinite(()));
    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::Ready, "Should be EscapeStatus::Ready");

    account.set_escape_security_period(4200);
}

#[test]
fn set_escape_security_period_with_expired_escape() {
    let account = initialize_account();
        account.trigger_escape_guardian(Option::None);

    cheat_block_timestamp(account.contract_address, 7 * 24 * 60 * 60 * 2, CheatSpan::Indefinite(()));
    let (escape, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::Expired, "Should be EscapeStatus::Expired");
    assert_ne!(escape.ready_at, 0, "Should not be 0");

    account.set_escape_security_period(4200);

    let new_escape_security_period = account.get_escape_security_period();
    assert_eq!(new_escape_security_period, 4200, "Escape security period should be 4200");
    let (new_escape, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::None, "Should be EscapeStatus::None");
    assert_eq!(new_escape.ready_at, 0, "New escape ready_at should be 0");
}

#[test]
fn set_escape_security_period_get_escape_status() {
    let account = initialize_account();
    account.set_escape_security_period(4200);

    let (_, no_escape) = account.get_escape_and_status();
    assert_eq!(no_escape, EscapeStatus::None, "Should be EscapeStatus::None");

    cheat_block_timestamp(account.contract_address, 100, CheatSpan::Indefinite(()));
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));

    cheat_block_timestamp(account.contract_address, 100 + 4200 - 1, CheatSpan::Indefinite(()));
    let (_, not_ready) = account.get_escape_and_status();
    assert_eq!(not_ready, EscapeStatus::NotReady, "Should be EscapeStatus::NotReady");

    cheat_block_timestamp(account.contract_address, 100 + 4200, CheatSpan::Indefinite(()));
    let (_, ready_early) = account.get_escape_and_status();
    assert_eq!(ready_early, EscapeStatus::Ready, "Should be EscapeStatus::Ready 1");

    cheat_block_timestamp(account.contract_address, 100 + (4200 * 2) - 1, CheatSpan::Indefinite(()));
    let (_, ready_late) = account.get_escape_and_status();
    assert_eq!(ready_late, EscapeStatus::Ready, "Should be EscapeStatus::Ready 2");

    cheat_block_timestamp(account.contract_address, 100 + (4200 * 2), CheatSpan::Indefinite(()));
    let (_, expired) = account.get_escape_and_status();
    assert_eq!(expired, EscapeStatus::Expired, "Should be EscapeStatus::Expired");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn set_escape_security_period_outside() {
    let account = initialize_account();
    cheat_caller_address(account.contract_address, 'another caller'.try_into().unwrap(), CheatSpan::Indefinite(()));
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
    cheat_block_timestamp(account.contract_address, 100, CheatSpan::Indefinite(()));
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    cheat_block_timestamp(account.contract_address, 100 + 4200 - 1, CheatSpan::Indefinite(()));
    account.escape_owner();
}

#[test]
fn set_escape_security_period_escape_escape() {
    let account = initialize_account();
    account.set_escape_security_period(4200);
    cheat_block_timestamp(account.contract_address, 100, CheatSpan::Indefinite(()));
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    cheat_block_timestamp(account.contract_address, 100 + 4200, CheatSpan::Indefinite(()));
    account.escape_owner();
    let new_owner = account.get_owner();
    assert_eq!(new_owner, 12, "Wrong new owner");
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn set_escape_security_period_escape_escape_too_late() {
    let account = initialize_account();
    account.set_escape_security_period(4200);
    cheat_block_timestamp(account.contract_address, 100, CheatSpan::Indefinite(()));
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    cheat_block_timestamp(account.contract_address, 100 + (4200 * 2), CheatSpan::Indefinite(()));
    account.escape_owner();
}

#[test]
fn escape_owner_default() {
    let account = initialize_account();
    cheat_block_timestamp(account.contract_address, 100, CheatSpan::Indefinite(()));
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    cheat_block_timestamp(account.contract_address, 100 + 7 * 24 * 60 * 60, CheatSpan::Indefinite(()));
    account.escape_owner();
    let new_owner = account.get_owner();
    assert_eq!(new_owner, 12, "Wrong new owner");
}
