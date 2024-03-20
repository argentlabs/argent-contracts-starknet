use argent::mocks::recovery_mocks::ThresholdRecoveryMock;
use argent::multisig::interface::IArgentMultisigInternal;
use argent::multisig::interface::{IArgentMultisig, IArgentMultisigDispatcher, IArgentMultisigDispatcherTrait};
use argent::recovery::interface::{IRecovery, IRecoveryDispatcher, IRecoveryDispatcherTrait, EscapeStatus};
use argent::recovery::threshold_recovery::{
    IToggleThresholdRecovery, IToggleThresholdRecoveryDispatcher, IToggleThresholdRecoveryDispatcherTrait
};
use argent::recovery::{threshold_recovery::threshold_recovery_component};
use argent::signer::{signer_signature::{Signer, StarknetSigner, starknet_signer_from_pubkey, SignerTrait}};
use argent::signer_storage::signer_list::signer_list_component;
use snforge_std::{
    start_prank, stop_prank, start_warp, CheatTarget, test_address, declare, ContractClassTrait, ContractClass
};
use starknet::SyscallResultTrait;
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
    let contract_class = declare("ThresholdRecoveryMock");
    let constructor = array![];
    let contract_address = contract_class.deploy(@constructor).expect('Deployment failed');

    start_prank(CheatTarget::One(contract_address), contract_address);
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
    assert_eq!(config.is_enabled, 1, "should be enabled");
    assert_eq!(config.security_period, 10, "should be 10");
    assert_eq!(config.expiry_period, 10, "should be 10");
    toggle_component.toggle_escape(false, 0, 0);
    config = component.get_escape_enabled();
    assert_eq!(config.is_enabled, 0, "should not be enabled");
    assert_eq!(config.security_period, 0, "should be 0");
    assert_eq!(config.expiry_period, 0, "should be 0");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_toggle_unauthorised() {
    let (_, toggle_component, _) = setup();
    start_prank(CheatTarget::All, (contract_address_const::<42>()));
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
fn test_trigger_escape_unauthorised() {
    let (component, _, _) = setup();
    start_prank(CheatTarget::All, (contract_address_const::<42>()));
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
}

// Escape

#[test]
fn test_execute_escape() {
    let (component, _, multisig_component) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    start_warp(CheatTarget::All, 11);
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
    start_warp(CheatTarget::All, 8);
    component.execute_escape();
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_Expired() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    start_warp(CheatTarget::All, 28);
    component.execute_escape();
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_execute_escape_unauthorised() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    start_warp(CheatTarget::All, 11);
    start_prank(CheatTarget::All, (contract_address_const::<42>()));
    component.execute_escape();
}

// Cancel

#[test]
fn test_cancel_escape() {
    let (component, _, multisig_component) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    start_warp(CheatTarget::All, 11);
    component.cancel_escape();
    let (escape, status) = component.get_escape();
    assert_eq!(status, EscapeStatus::None, "status should be None");
    assert_eq!(escape.ready_at, 0, "should be no recovery");
    assert!(multisig_component.is_signer(SIGNER_1()), "should be signer 1");
    assert!(multisig_component.is_signer(SIGNER_2()), "should be signer 2");
    assert!(!multisig_component.is_signer(SIGNER_3()), "should not be signer 3");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_cancel_escape_unauthorised() {
    let (component, _, _) = setup();
    component.trigger_escape(array![SIGNER_2()], array![SIGNER_3()]);
    start_warp(CheatTarget::All, 11);
    start_prank(CheatTarget::All, (contract_address_const::<42>()));
    component.cancel_escape();
}

