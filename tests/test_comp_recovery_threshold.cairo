use argent::mocks::recovery_mocks::ThresholdRecoveryMock;
use argent::multisig::interface::{IArgentMultisigDispatcher, IArgentMultisigDispatcherTrait};
use argent::recovery::interface::{IRecoveryDispatcher, IRecoveryDispatcherTrait, EscapeStatus};
use argent::recovery::threshold_recovery::{
    threshold_recovery_component, IToggleThresholdRecoveryDispatcher, IToggleThresholdRecoveryDispatcherTrait
};
use argent::signer::signer_signature::{Signer, starknet_signer_from_pubkey, SignerTrait};
use snforge_std::{
    EventSpyTrait, cheat_caller_address_global, cheat_block_timestamp_global, declare, ContractClassTrait,
    EventSpyAssertionsTrait, spy_events,
};
use starknet::{ContractAddress, contract_address_const,};
use super::setup::constants::{MULTISIG_OWNER};

fn SIGNER_1() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey)
}

fn SIGNER_2() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey)
}

fn SIGNER_3() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey)
}

fn setup() -> (IRecoveryDispatcher, IToggleThresholdRecoveryDispatcher, IArgentMultisigDispatcher) {
    let contract_class = declare("ThresholdRecoveryMock").expect('Failed ThresholdRecoveryMock');
    let constructor = array![];
    let (contract_address, _) = contract_class.deploy(@constructor).expect('Deployment failed');

    cheat_caller_address_global(contract_address);
    IArgentMultisigDispatcher { contract_address }.add_signers(2, array![SIGNER_1(), SIGNER_2()]);
    IToggleThresholdRecoveryDispatcher { contract_address }.toggle_escape(true, 10, 10);
    (
        IRecoveryDispatcher { contract_address },
        IToggleThresholdRecoveryDispatcher { contract_address },
        IArgentMultisigDispatcher { contract_address }
    )
}

// Toggle

#[test]
fn test_toggle_escape() {
    let (component, toggle_component, _) = setup();
    let mut config = component.get_escape_enabled();
    assert_eq!(config.is_enabled, true, "should be enabled");
    assert_eq!(config.security_period, 10, "should be 10");
    assert_eq!(config.expiry_period, 10, "should be 10");
    toggle_component.toggle_escape(false, 0, 0);
    config = component.get_escape_enabled();
    assert_eq!(config.is_enabled, false, "should not be enabled");
    assert_eq!(config.security_period, 0, "should be 0");
    assert_eq!(config.expiry_period, 0, "should be 0");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_toggle_unauthorized() {
    let (_, toggle_component, _) = setup();
    cheat_caller_address_global((contract_address_const::<42>()));
    toggle_component.toggle_escape(false, 0, 0);
}

// Trigger

#[test]
fn test_trigger_escape_first_signer() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_1()], array![SIGNER_3()]);
    let (escape, status) = component.get_escape();
    assert_eq!(
        *escape.target_signers.at(0),
        starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey).into_guid(),
        "should be signer 1"
    );
    assert_eq!(
        *escape.new_signers.at(0),
        starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey).into_guid(),
        "should be signer 3"
    );

    assert_eq!(escape.ready_at, 10, "should be 10");
    assert_eq!(status, EscapeStatus::NotReady, "should be NotReady");
}

#[test]
fn test_trigger_escape_last_signer() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    let (escape, status) = component.get_escape();
    assert_eq!(
        *escape.target_signers.at(0),
        starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey).into_guid(),
        "should be signer 2"
    );
    assert_eq!(
        *escape.new_signers.at(0),
        starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey).into_guid(),
        "should be signer 3"
    );

    assert_eq!(escape.ready_at, 10, "should be 10");
    assert_eq!(status, EscapeStatus::NotReady, "should be NotReady");
}

#[test]
fn test_trigger_escape_can_override() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_1()], array![SIGNER_3()]);
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    let (escape, _) = component.get_escape();
    assert_eq!(
        *escape.target_signers.at(0),
        starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey,).into_guid(),
        "should be signer 2"
    );
    assert_eq!(
        *escape.new_signers.at(0),
        starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey,).into_guid(),
        "should be signer 3"
    );
}

#[test]
#[should_panic(expected: ('argent/cannot-override-escape',))]
fn test_trigger_escape_cannot_override() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    component.trigger_escape(array![SIGNER_1()], array![SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('argent/invalid-escape-length',))]
fn test_trigger_escape_invalid_input() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3(), SIGNER_1()]);
}

#[test]
#[should_panic(expected: ('argent/escape-disabled',))]
fn test_trigger_escape_not_enabled() {
    let (component, toggle_component, _) = setup();
    toggle_component.toggle_escape(false, 0, 0);
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_trigger_escape_unauthorized() {
    let (component, _, _) = setup();
    cheat_caller_address_global((contract_address_const::<42>()));
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
}

// Escape

#[test]
fn test_execute_escape() {
    let (component, _, multisig_component) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    cheat_block_timestamp_global(11);
    component.execute_escape();
    let (escape, status) = component.get_escape();
    assert_eq!(status, EscapeStatus::None, "status should be None");
    assert_eq!(escape.ready_at, 0, "should be no recovery");
    assert!(multisig_component.is_signer(SIGNER_1()), "should be signer 1");
    assert!(multisig_component.is_signer(SIGNER_3()), "should be signer 3");
    assert!(!multisig_component.is_signer(SIGNER_2()), "should not be signer 2");
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_NotReady() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    cheat_block_timestamp_global(8);
    component.execute_escape();
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_Expired() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    cheat_block_timestamp_global(28);
    component.execute_escape();
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_execute_escape_unauthorized() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    cheat_block_timestamp_global(11);
    cheat_caller_address_global((contract_address_const::<42>()));
    component.execute_escape();
}

// Cancel

#[test]
fn test_cancel_escape() {
    let (component, _, multisig_component) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    cheat_block_timestamp_global(11);
    let mut spy = spy_events();
    component.cancel_escape();
    let (escape, status) = component.get_escape();
    assert_eq!(status, EscapeStatus::None, "status should be None");
    assert_eq!(escape.ready_at, 0, "should be no recovery");
    assert!(multisig_component.is_signer(SIGNER_1()), "should be signer 1");
    assert!(multisig_component.is_signer(SIGNER_2()), "should be signer 2");
    assert!(!multisig_component.is_signer(SIGNER_3()), "should not be signer 3");

    let event = threshold_recovery_component::Event::EscapeCanceled(
        threshold_recovery_component::EscapeCanceled {
            target_signers: array![SIGNER_2().into_guid()].span(), new_signers: array![SIGNER_3().into_guid()].span(),
        }
    );
    spy.assert_emitted(@array![(component.contract_address, event)]);

    assert_eq!(spy.get_events().events.len(), 1, "excess events");
}

#[test]
fn test_cancel_escape_expired() {
    let (component, _, multisig_component) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    cheat_block_timestamp_global(21);
    let mut spy = spy_events();
    component.cancel_escape();
    let (escape, status) = component.get_escape();
    assert_eq!(status, EscapeStatus::None, "status should be None");
    assert_eq!(escape.ready_at, 0, "should be no recovery");
    assert!(multisig_component.is_signer(SIGNER_1()), "should be signer 1");
    assert!(multisig_component.is_signer(SIGNER_2()), "should be signer 2");
    assert!(!multisig_component.is_signer(SIGNER_3()), "should not be signer 3");

    let event = threshold_recovery_component::Event::EscapeCanceled(
        threshold_recovery_component::EscapeCanceled {
            target_signers: array![SIGNER_2().into_guid()].span(), new_signers: array![SIGNER_3().into_guid()].span(),
        }
    );
    spy.assert_not_emitted(@array![(component.contract_address, event)]);

    assert_eq!(spy.get_events().events.len(), 0, "excess events");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_cancel_escape_unauthorized() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    cheat_block_timestamp_global(11);
    cheat_caller_address_global((contract_address_const::<42>()));
    component.cancel_escape();
}

