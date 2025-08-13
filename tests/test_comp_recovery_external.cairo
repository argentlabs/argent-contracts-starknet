use argent::multisig_account::external_recovery::{
    EscapeCall, EscapeCanceled, EscapeTriggered, IExternalRecoveryDispatcher, IExternalRecoveryDispatcherTrait,
    external_recovery_component, get_escape_call_hash,
};
use argent::multisig_account::signer_manager::{ISignerManagerDispatcher, ISignerManagerDispatcherTrait};
use argent::recovery::EscapeStatus;
use argent::signer::signer_signature::Signer;
use argent::utils::serialization::serialize;
use crate::{SIGNER_1, SIGNER_2, SIGNER_3, SIGNER_4};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, EventSpyTrait, declare, spy_events,
    start_cheat_block_timestamp_global, start_cheat_caller_address_global,
};
use starknet::{ContractAddress, contract_address_const};

fn GUARDIAN() -> ContractAddress {
    contract_address_const::<'guardian'>()
}

fn setup() -> (IExternalRecoveryDispatcher, ISignerManagerDispatcher) {
    let (contract_address, _) = declare("ExternalRecoveryMock")
        .expect('Fail depl ExternalRecoveryMock')
        .contract_class()
        .deploy(@array![])
        .expect('Deployment failed');
    start_cheat_caller_address_global(contract_address);
    ISignerManagerDispatcher { contract_address }.add_signers(2, array![SIGNER_1(), SIGNER_2()]);
    IExternalRecoveryDispatcher { contract_address }.toggle_escape(true, (10 * 60), (10 * 60), GUARDIAN());
    (IExternalRecoveryDispatcher { contract_address }, ISignerManagerDispatcher { contract_address })
}

// Toggle

#[test]
fn test_toggle_escape() {
    let (component, _) = setup();
    let mut config = component.get_escape_enabled();
    assert!(config.is_enabled);
    assert_eq!(config.security_period, 10 * 60);
    assert_eq!(config.expiry_period, 10 * 60);
    assert_eq!(component.get_guardian(), GUARDIAN());

    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None);

    component.toggle_escape(false, 0, 0, contract_address_const::<0>());
    config = component.get_escape_enabled();
    assert_eq!(config.is_enabled, false);
    assert_eq!(config.security_period, 0);
    assert_eq!(config.expiry_period, 0);
    assert_eq!(component.get_guardian(), contract_address_const::<0>());
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_toggle_unauthorized() {
    let (component, _) = setup();
    start_cheat_caller_address_global(contract_address_const::<42>());
    component.toggle_escape(false, 0, 0, contract_address_const::<0>());
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
    component.toggle_escape(true, (10 * 60) - 1, (10 * 60), contract_address_const::<0>());
}

#[test]
#[should_panic(expected: ('argent/invalid-expiry-period',))]
fn test_toggle_small_expiry_period() {
    let (component, _) = setup();
    component.toggle_escape(true, (10 * 60), (10 * 60) - 1, contract_address_const::<0>());
}


#[test]
#[should_panic(expected: ('argent/invalid-zero-guardian',))]
fn test_toggle_zero_guardian() {
    let (component, _) = setup();
    component.toggle_escape(true, (10 * 60), (10 * 60), contract_address_const::<0>());
}

fn replace_signer_call(remove: Signer, replace_with: Signer) -> EscapeCall {
    EscapeCall { selector: selector!("replace_signer"), calldata: serialize(@(remove, replace_with)) }
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle__true_with_not_ready_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    start_cheat_caller_address_global(GUARDIAN());
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::NotReady);

    start_cheat_caller_address_global(contract_address);
    component.toggle_escape(true, (10 * 60), (10 * 60), contract_address_const::<42>());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_false_with_not_ready_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    start_cheat_caller_address_global(GUARDIAN());
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::NotReady);

    start_cheat_caller_address_global(contract_address);
    component.toggle_escape(false, (10 * 60), (10 * 60), contract_address_const::<42>());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_true_with_ready_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    start_cheat_caller_address_global(GUARDIAN());
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    start_cheat_block_timestamp_global(10 * 60);
    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Ready);

    start_cheat_caller_address_global(contract_address);
    component.toggle_escape(true, (10 * 60), (10 * 60), contract_address_const::<42>());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_false_with_ready_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    start_cheat_caller_address_global(GUARDIAN());
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    start_cheat_block_timestamp_global(10 * 60);
    let (_, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Ready);

    start_cheat_caller_address_global(contract_address);
    component.toggle_escape(false, (10 * 60), (10 * 60), contract_address_const::<42>());
}

#[test]
fn test_toggle_true_with_expired_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    start_cheat_caller_address_global(GUARDIAN());
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    start_cheat_block_timestamp_global(2 * 10 * 60);
    let (escape, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Expired);
    assert_ne!(escape.ready_at, 0, "Should not be 0");

    start_cheat_caller_address_global(contract_address);
    component.toggle_escape(true, (10 * 60), (10 * 60), contract_address_const::<42>());

    let (escape, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None);
    assert_eq!(escape.ready_at, 0);
}

#[test]
fn test_toggle_false_with_expired_escape() {
    let (component, _) = setup();
    let contract_address = component.contract_address;

    start_cheat_caller_address_global(GUARDIAN());
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    component.trigger_escape(call);

    start_cheat_block_timestamp_global(2 * 10 * 60);
    let (escape, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Expired);
    assert_ne!(escape.ready_at, 0, "Should not be 0");

    start_cheat_caller_address_global(contract_address);
    component.toggle_escape(false, 0, 0, contract_address_const::<0>());

    let (escape, escape_status) = component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None);
    assert_eq!(escape.ready_at, 0);
}

// Trigger

#[test]
fn test_trigger_escape_replace_signer() {
    let (component, _) = setup();
    start_cheat_caller_address_global(GUARDIAN());
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    let call_hash = get_escape_call_hash(@call);
    component.trigger_escape(call);
    let (escape, status) = component.get_escape();
    assert_eq!(escape.call_hash, call_hash);
    assert_eq!(escape.ready_at, 10 * 60);
    assert_eq!(status, EscapeStatus::NotReady);
}

#[test]
fn test_trigger_escape_can_override() {
    let (component, _) = setup();
    start_cheat_caller_address_global(GUARDIAN());

    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_4()));
    let second_call = replace_signer_call(SIGNER_1(), SIGNER_3());
    let second_call_hash = get_escape_call_hash(@second_call);

    let mut spy = spy_events();
    component.trigger_escape(second_call);
    let first_call_hash = get_escape_call_hash(@replace_signer_call(SIGNER_1(), SIGNER_4()));
    let escape_canceled_event = external_recovery_component::Event::EscapeCanceled(
        EscapeCanceled { call_hash: first_call_hash },
    );
    spy.assert_emitted(@array![(component.contract_address, escape_canceled_event)]);

    let escape_event = external_recovery_component::Event::EscapeTriggered(
        EscapeTriggered { ready_at: 10 * 60, call: replace_signer_call(SIGNER_1(), SIGNER_3()) },
    );
    spy.assert_emitted(@array![(component.contract_address, escape_event)]);
    assert_eq!(spy.get_events().events.len(), 2);

    let (escape, _) = component.get_escape();
    assert_eq!(escape.call_hash, second_call_hash);
}

#[test]
#[should_panic(expected: ('argent/only-guardian',))]
fn test_trigger_escape_not_enabled() {
    let (component, _) = setup();
    component.toggle_escape(false, 0, 0, contract_address_const::<0>());
    start_cheat_caller_address_global(GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_3()));
}

#[test]
#[should_panic(expected: ('argent/only-guardian',))]
fn test_trigger_escape_unauthorized() {
    let (component, _) = setup();
    start_cheat_caller_address_global(contract_address_const::<42>());
    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_3()));
}

// Escape

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_NotReady() {
    let (component, _) = setup();
    start_cheat_caller_address_global(GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_cheat_block_timestamp_global(8);
    component.execute_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_Expired() {
    let (component, _) = setup();
    start_cheat_caller_address_global(GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_cheat_block_timestamp_global(28);
    component.execute_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
}

// Cancel

#[test]
fn test_cancel_escape() {
    let (component, multisig_component) = setup();
    start_cheat_caller_address_global(GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_cheat_block_timestamp_global(11);
    start_cheat_caller_address_global(component.contract_address);
    let mut spy = spy_events();
    component.cancel_escape();
    let (escape, status) = component.get_escape();
    assert_eq!(status, EscapeStatus::None);
    assert_eq!(escape.ready_at, 0);
    assert!(multisig_component.is_signer(SIGNER_1()));
    assert!(multisig_component.is_signer(SIGNER_2()));
    assert!(!multisig_component.is_signer(SIGNER_3()));

    let call_hash = get_escape_call_hash(@replace_signer_call(SIGNER_2(), SIGNER_3()));
    assert_eq!(spy.get_events().events.len(), 1);
    let event = external_recovery_component::Event::EscapeCanceled(EscapeCanceled { call_hash });
    spy.assert_emitted(@array![(component.contract_address, event)]);
}

#[test]
fn test_cancel_escape_expired() {
    let (component, multisig_component) = setup();
    start_cheat_caller_address_global(GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_cheat_block_timestamp_global(2 * (60 * 10) + 1);
    start_cheat_caller_address_global(component.contract_address);
    let mut spy = spy_events();
    component.cancel_escape();
    let (escape, status) = component.get_escape();
    assert_eq!(status, EscapeStatus::None);
    assert_eq!(escape.ready_at, 0);
    assert!(multisig_component.is_signer(SIGNER_1()));
    assert!(multisig_component.is_signer(SIGNER_2()));
    assert!(!multisig_component.is_signer(SIGNER_3()));

    let call_hash = get_escape_call_hash(@replace_signer_call(SIGNER_2(), SIGNER_3()));
    assert_eq!(spy.get_events().events.len(), 0);
    let event = external_recovery_component::Event::EscapeCanceled(EscapeCanceled { call_hash: call_hash });
    spy.assert_not_emitted(@array![(component.contract_address, event)]);
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_cancel_escape_unauthorized() {
    let (component, _) = setup();
    start_cheat_caller_address_global(GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_cheat_block_timestamp_global(11);
    start_cheat_caller_address_global(contract_address_const::<42>());
    component.cancel_escape();
}

