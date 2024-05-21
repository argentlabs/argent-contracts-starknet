use argent::presets::argent_account::ArgentAccount;
use argent::recovery::interface::EscapeStatus;
use argent::signer::signer_signature::starknet_signer_from_pubkey;
use snforge_std::{spy_events, start_warp, SpyOn, start_prank, CheatTarget, EventAssertions};
use super::setup::account_test_setup::{ITestArgentAccountDispatcherTrait, initialize_account};

#[test]
fn set_escape_security_period() {
    let account = initialize_account();
    let default_escape_security_period = account.get_escape_security_period();
    assert_eq!(default_escape_security_period, consteval_int!(7 * 24 * 60 * 60), "Default value incorrect");

    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::None, "Should be EscapeStatus::None");

    let mut spy = spy_events(SpyOn::One(account.contract_address));
    account.set_escape_security_period(4200);
    let new_escape_security_period = account.get_escape_security_period();
    assert_eq!(new_escape_security_period, 4200, "New value incorrect");

    let event = ArgentAccount::Event::EscapeSecurityPeriodChanged(
        ArgentAccount::EscapeSecurityPeriodChanged { escape_security_period: 4200 }
    );
    spy.assert_emitted(@array![(account.contract_address, event)]);
    assert_eq!(spy.events.len(), 0, "excess events");
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn set_escape_security_period_with_not_ready_escape() {
    let account = initialize_account();
    let default_escape_security_period = account.get_escape_security_period();
    assert_eq!(default_escape_security_period, consteval_int!(7 * 24 * 60 * 60), "Default value incorrect");

    account.trigger_escape_guardian(Option::None);

    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::NotReady, "Should be EscapeStatus::NotReady");
    account.set_escape_security_period(4200);
}


#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn set_escape_security_period_with_ready_escape() {
    let account = initialize_account();
    let default_escape_security_period = account.get_escape_security_period();
    assert_eq!(default_escape_security_period, consteval_int!(7 * 24 * 60 * 60), "Default value incorrect");

    account.trigger_escape_guardian(Option::None);

    start_warp(CheatTarget::One(account.contract_address), consteval_int!(7 * 24 * 60 * 60));
    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::Ready, "Should be EscapeStatus::Ready");
    account.set_escape_security_period(4200);
}

#[test]
fn set_escape_security_period_with_expired_escape() {
    let account = initialize_account();
    let default_escape_security_period = account.get_escape_security_period();
    assert_eq!(default_escape_security_period, consteval_int!(7 * 24 * 60 * 60), "Default value incorrect");

    account.trigger_escape_guardian(Option::None);

    start_warp(CheatTarget::One(account.contract_address), consteval_int!(7 * 24 * 60 * 60 * 2));
    let (_, status) = account.get_escape_and_status();
    assert_eq!(status, EscapeStatus::Expired, "Should be EscapeStatus::Expired");
    account.set_escape_security_period(4200);

    let new_escape_security_period = account.get_escape_security_period();
    assert_eq!(new_escape_security_period, 4200, "New value incorrect");

    let (new_escape, _) = account.get_escape_and_status();
    assert_eq!(new_escape.ready_at, 0, "New escape ready_at should be 0");
}

#[test]
fn set_escape_security_period_get_escape_status() {
    let account = initialize_account();
    account.set_escape_security_period(4200);

    let (_, no_escape) = account.get_escape_and_status();
    assert_eq!(no_escape, EscapeStatus::None, "Should be EscapeStatus::None");

    start_warp(CheatTarget::One(account.contract_address), 100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));

    start_warp(CheatTarget::One(account.contract_address), 100 + 4200 - 1);
    let (_, not_ready) = account.get_escape_and_status();
    assert_eq!(not_ready, EscapeStatus::NotReady, "Should be EscapeStatus::NotReady");

    start_warp(CheatTarget::One(account.contract_address), 100 + 4200);
    let (_, ready_early) = account.get_escape_and_status();
    assert_eq!(ready_early, EscapeStatus::Ready, "Should be EscapeStatus::Ready 1");

    start_warp(CheatTarget::One(account.contract_address), 100 + (4200 * 2) - 1);
    let (_, ready_late) = account.get_escape_and_status();
    assert_eq!(ready_late, EscapeStatus::Ready, "Should be EscapeStatus::Ready 2");

    start_warp(CheatTarget::One(account.contract_address), 100 + (4200 * 2));
    let (_, expired) = account.get_escape_and_status();
    assert_eq!(expired, EscapeStatus::Expired, "Should be EscapeStatus::Expired");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn set_escape_security_period_outside() {
    let account = initialize_account();
    start_prank(CheatTarget::One(account.contract_address), 'another caller'.try_into().unwrap());
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
    start_warp(CheatTarget::One(account.contract_address), 100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    start_warp(CheatTarget::One(account.contract_address), 100 + 4200 - 1);
    account.escape_owner();
}

#[test]
fn set_escape_security_period_escape_escape() {
    let account = initialize_account();
    account.set_escape_security_period(4200);
    start_warp(CheatTarget::One(account.contract_address), 100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    start_warp(CheatTarget::One(account.contract_address), 100 + 4200);
    account.escape_owner();
    let new_owner = account.get_owner();
    assert_eq!(new_owner, 12, "Wrong new owner");
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn set_escape_security_period_escape_escape_too_late() {
    let account = initialize_account();
    account.set_escape_security_period(4200);
    start_warp(CheatTarget::One(account.contract_address), 100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    start_warp(CheatTarget::One(account.contract_address), 100 + (4200 * 2));
    account.escape_owner();
}


#[test]
fn escape_owner_default() {
    let account = initialize_account();
    start_warp(CheatTarget::One(account.contract_address), 100);
    account.trigger_escape_owner(starknet_signer_from_pubkey(12));
    start_warp(CheatTarget::One(account.contract_address), 100 + consteval_int!(7 * 24 * 60 * 60));
    account.escape_owner();
    let new_owner = account.get_owner();
    assert_eq!(new_owner, 12, "Wrong new owner");
}
