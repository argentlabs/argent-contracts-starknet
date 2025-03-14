use argent::external_recovery::external_recovery::{EscapeCall, external_recovery_component, get_escape_call_hash};
use argent::external_recovery::interface::{
    Escape, IExternalRecovery, IExternalRecoveryDispatcher, IExternalRecoveryDispatcherTrait,
};
use argent::mocks::recovery_mocks::ExternalRecoveryMock;
use argent::multisig::interface::{
    IArgentMultisig, IArgentMultisigDispatcher, IArgentMultisigDispatcherTrait, IArgentMultisigInternal,
};
use argent::recovery::interface::EscapeStatus;
use argent::signer::signer_signature::{Signer, SignerTrait, StarknetSigner, starknet_signer_from_pubkey};
use argent::signer_storage::signer_list::signer_list_component;
use argent::utils::serialization::serialize;
use core::traits::TryInto;
use snforge_std::{
    CheatSpan, ContractClass, ContractClassTrait, EventAssertions, EventFetcher, EventSpy, SpyOn, declare, spy_events,
    cheat_caller_address, cheat_block_timestamp, stop_prank, test_address, EventSpyAssertionsTrait
};
use starknet::{ContractAddress, SyscallResultTrait, deploy_syscall};
use super::setup::constants::MULTISIG_OWNER;

fn SIGNER_1() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey)
}

fn SIGNER_2() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey)
}

fn SIGNER_3() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey)
}

fn SIGNER_4() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(4).pubkey)
}

fn GUARDIAN() -> ContractAddress {
    let guardian_value: felt252 = 'guardian';
    guardian_value.try_into().unwrap()
}

fn ZERO_ADDRESS() -> ContractAddress {
    0.try_into().unwrap()
}

fn setup() -> (IExternalRecoveryDispatcher, IArgentMultisigDispatcher) {
    let contract_address = declare("ExternalRecoveryMock").deploy(@array![]).expect('Deployment failed');
    cheat_caller_address(contract_address, contract_address, CheatSpan::Indefinite(()));
    IArgentMultisigDispatcher { contract_address }.add_signers(2, array![SIGNER_1(), SIGNER_2()]);
    IExternalRecoveryDispatcher { contract_address }.toggle_escape(true, (10 * 60), (10 * 60), GUARDIAN());
    (IExternalRecoveryDispatcher { contract_address }, IArgentMultisigDispatcher { contract_address })
}

// Toggle

#[test]
fn test_toggle_escape() {
    let (component, _) = setup();
    let mut config = component.get_escape_enabled();
    assert!(config.is_enabled, "should be enabled");
    assert_eq!(config.security_period, 10 * 60, "should be 600");
    assert_eq!(config.expiry_period, 10 * 60, "should be 600");
    assert_eq!(component.get_guardian(), GUARDIAN(), "should be guardian");

    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None, "should be None");

    component.toggle_escape(false, 0, 0, ZERO_ADDRESS());
    config = component.get_escape_enabled();
    assert_eq!(config.is_enabled, false, "should not be enabled");
    assert_eq!(config.security_period, 0, "should be 0");
    assert_eq!(config.expiry_period, 0, "should be 0");
    assert_eq!(component.get_guardian(), ZERO_ADDRESS(), "guardian should be 0");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_toggle_unauthorized() {
    let (component, _) = setup();
    cheat_caller_address(component.contract_address, 42.try_into().unwrap(), CheatSpan::Indefinite(()));
    component.toggle_escape(false, 0, 0, ZERO_ADDRESS());
}

#[test]
#[should_panic(expected: ('argent/invalid-guardian',))]
fn test_toggle_guardian_same_as_account() {
    let (component, _) = setup();
    component.toggle_escape(true, 10 * 60, 10 * 60, component.contract_address);
}

#[test]
#[should_panic(expected: ('argent/invalid-security-period',))]
fn test_toggle_small_security_period() {
    let (component, _) = setup();
    component.toggle_escape(true, (10 * 60) - 1, (10 * 60), ZERO_ADDRESS());
}

#[test]
#[should_panic(expected: ('argent/invalid-expiry-period',))]
fn test_toggle_small_expiry_period() {
    let (component, _) = setup();
    component.toggle_escape(true, (10 * 60), (10 * 60) - 1, ZERO_ADDRESS());
}


#[test]
#[should_panic(expected: ('argent/invalid-zero-guardian',))]
fn test_toggle_zero_guardian() {
    let (component, _) = setup();
    component.toggle_escape(true, (10 * 60), (10 * 60), ZERO_ADDRESS());
}

fn replace_signer_call(remove: Signer, replace_with: Signer) -> EscapeCall {
    EscapeCall { selector: selector!("replace_signer"), calldata: serialize(@(remove, replace_with)) }
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle__true_with_not_ready_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::NotReady, "should be NotReady");

    cheat_caller_address(contract_address, contract_address, CheatSpan::Indefinite(()));
    component.toggle_escape(true, (10 * 60), (10 * 60), 42.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_false_with_not_ready_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::NotReady, "should be NotReady");

    cheat_caller_address(contract_address, contract_address, CheatSpan::Indefinite(()));
    component.toggle_escape(false, (10 * 60), (10 * 60), 42.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_true_with_ready_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    cheat_block_timestamp(component.contract_address, 10 * 60, CheatSpan::Indefinite(()));
    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Ready, "should be Ready");

    cheat_caller_address(component.contract_address, contract_address, CheatSpan::Indefinite(()));
    component.toggle_escape(true, (10 * 60), (10 * 60), 42.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_false_with_ready_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    cheat_block_timestamp(component.contract_address, 10 * 60, CheatSpan::Indefinite(()));
    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Ready, "should be Ready");

    cheat_caller_address(component.contract_address, contract_address, CheatSpan::Indefinite(()));
    component.toggle_escape(false, (10 * 60), (10 * 60), 42.try_into().unwrap());
}

#[test]
fn test_toggle_true_with_expired_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    cheat_block_timestamp(component.contract_address, 2 * 10 * 60, CheatSpan::Indefinite(()));
    let (escape, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Expired, "should be Expired");
    assert_ne!(escape.ready_at, 0, "Should not be 0");

    cheat_caller_address(contract_address, contract_address, CheatSpan::Indefinite(()));
    component.toggle_escape(true, (10 * 60), (10 * 60), 42.try_into().unwrap());

    let (escape, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None, "should be None");
    assert_eq!(escape.ready_at, 0, "Should be 0");
}

#[test]
fn test_toggle_false_with_expired_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    cheat_block_timestamp(component.contract_address, 2 * 10 * 60, CheatSpan::Indefinite(()));
    let (escape, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Expired, "should be Expired");
    assert_ne!(escape.ready_at, 0, "Should not be 0");

    cheat_caller_address(contract_address, contract_address, CheatSpan::Indefinite(()));
    component.toggle_escape(false, 0, 0, ZERO_ADDRESS());

    let (escape, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None, "should be None");
    assert_eq!(escape.ready_at, 0, "Should be 0");
}

// Trigger

#[test]
fn test_trigger_escape_replace_signer() {
    let (component, _) = setup();
    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    let call_hash = get_escape_call_hash(@call);
    component.trigger_escape(call);
    let (escape, status) = component.get_escape();
    assert_eq!(escape.call_hash, call_hash, "invalid call hash");
    assert_eq!(escape.ready_at, 10 * 60, "should be 600");
    assert_eq!(status, EscapeStatus::NotReady, "should be NotReady");
}

#[test]
fn test_trigger_escape_can_override() {
    let (component, _) = setup();
    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));

    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_4()));
    let second_call = replace_signer_call(SIGNER_1(), SIGNER_3());
    let second_call_hash = get_escape_call_hash(@second_call);

    let mut spy = spy_events(SpyOn::One(component.contract_address));
    component.trigger_escape(second_call);
    let first_call_hash = get_escape_call_hash(@replace_signer_call(SIGNER_1(), SIGNER_4()));
    let escape_canceled_event = external_recovery_component::Event::EscapeCanceled(
        external_recovery_component::EscapeCanceled { call_hash: first_call_hash },
    );
    spy.assert_emitted(@array![(component.contract_address, escape_canceled_event)]);

    let escape_event = external_recovery_component::Event::EscapeTriggered(
        external_recovery_component::EscapeTriggered {
            ready_at: 10 * 60, call: replace_signer_call(SIGNER_1(), SIGNER_3()),
        },
    );
    spy.assert_emitted(@array![(component.contract_address, escape_event)]);
    assert_eq!(spy.events.len(), 0, "excess events");

    let (escape, _) = component.get_escape();
    assert_eq!(escape.call_hash, second_call_hash, "invalid call hash");
}

#[test]
#[should_panic(expected: ('argent/only-guardian',))]
fn test_trigger_escape_not_enabled() {
    let (component, _) = setup();
    component.toggle_escape(false, 0, 0, ZERO_ADDRESS());
    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_3()));
}

#[test]
#[should_panic(expected: ('argent/only-guardian',))]
fn test_trigger_escape_unauthorized() {
    let (component, _) = setup();
    cheat_caller_address(component.contract_address, 42.try_into().unwrap(), CheatSpan::Indefinite(()));
    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_3()));
}

// Escape

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_NotReady() {
    let (component, _) = setup();
    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    cheat_block_timestamp(component.contract_address, 8, CheatSpan::Indefinite(()));
    component.execute_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_Expired() {
    let (component, _) = setup();
    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    cheat_block_timestamp(component.contract_address, 28, CheatSpan::Indefinite(()));
    component.execute_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
}

// Cancel

#[test]
fn test_cancel_escape() {
    let (component, multisig_component) = setup();
    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    cheat_block_timestamp(component.contract_address, 11, CheatSpan::Indefinite(()));
    cheat_caller_address(component.contract_address, component.contract_address, CheatSpan::Indefinite(()));
    let mut spy = spy_events(SpyOn::One(component.contract_address));
    component.cancel_escape();
    let (escape, status) = component.get_escape();
    assert_eq!(status, EscapeStatus::None, "status should be None");
    assert_eq!(escape.ready_at, 0, "should be no recovery");
    assert!(multisig_component.is_signer(SIGNER_1()), "should be signer 1");
    assert!(multisig_component.is_signer(SIGNER_2()), "should be signer 2");
    assert!(!multisig_component.is_signer(SIGNER_3()), "should not be signer 3");

    let call_hash = get_escape_call_hash(@replace_signer_call(SIGNER_2(), SIGNER_3()));
    let event = external_recovery_component::Event::EscapeCanceled(
        external_recovery_component::EscapeCanceled { call_hash },
    );
    spy.assert_emitted(@array![(component.contract_address, event)]);

    assert_eq!(spy.events.len(), 0, "excess events");
}

#[test]
fn test_cancel_escape_expired() {
    let (component, multisig_component) = setup();
    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    cheat_block_timestamp(component.contract_address, 2 * (60 * 10) + 1, CheatSpan::Indefinite(()));
    cheat_caller_address(component.contract_address, component.contract_address, CheatSpan::Indefinite(()));
    let mut spy = spy_events(SpyOn::One(component.contract_address));
    component.cancel_escape();
    let (escape, status) = component.get_escape();
    assert_eq!(status, EscapeStatus::None, "status should be None");
    assert_eq!(escape.ready_at, 0, "should be no recovery");
    assert!(multisig_component.is_signer(SIGNER_1()), "should be signer 1");
    assert!(multisig_component.is_signer(SIGNER_2()), "should be signer 2");
    assert!(!multisig_component.is_signer(SIGNER_3()), "should not be signer 3");

    let call_hash = get_escape_call_hash(@replace_signer_call(SIGNER_2(), SIGNER_3()));
    let event = external_recovery_component::Event::EscapeCanceled(
        external_recovery_component::EscapeCanceled { call_hash: call_hash },
    );
    spy.assert_not_emitted(@array![(component.contract_address, event)]);

    assert_eq!(spy.events.len(), 0, "excess events");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_cancel_escape_unauthorized() {
    let (component, _) = setup();
    cheat_caller_address(component.contract_address, GUARDIAN(), CheatSpan::Indefinite(()));
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    cheat_block_timestamp(component.contract_address, 11, CheatSpan::Indefinite(()));
    cheat_caller_address(component.contract_address, 42.try_into().unwrap(), CheatSpan::Indefinite(()));
    component.cancel_escape();
}
