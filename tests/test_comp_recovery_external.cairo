use argent::external_recovery::{
    interface::{IExternalRecovery, IExternalRecoveryDispatcher, IExternalRecoveryDispatcherTrait,},
    external_recovery::{external_recovery_component, EscapeCall, get_escape_call_hash}
};
use argent::mocks::recovery_mocks::ExternalRecoveryMock;
use argent::multisig::interface::IArgentMultisigInternal;
use argent::multisig::interface::{IArgentMultisig, IArgentMultisigDispatcher, IArgentMultisigDispatcherTrait};

use argent::recovery::interface::{EscapeStatus};
use argent::signer::{signer_signature::{Signer, StarknetSigner, starknet_signer_from_pubkey, SignerTrait}};
use argent::signer_storage::signer_list::signer_list_component;
use argent::utils::serialization::serialize;
use snforge_std::{
    start_prank, stop_prank, start_warp, CheatTarget, test_address, declare, ContractClassTrait, ContractClass
};
use starknet::SyscallResultTrait;
use starknet::{deploy_syscall, contract_address_const, ContractAddress,};
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

fn SIGNER_4() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(4).pubkey)
}

fn GUARDIAN() -> ContractAddress {
    contract_address_const::<'guardian'>()
}

fn setup() -> (IExternalRecoveryDispatcher, IArgentMultisigDispatcher) {
    let contract_address = declare("ExternalRecoveryMock").deploy(@array![]).expect('Deployment failed');
    start_prank(CheatTarget::One(contract_address), contract_address);
    IArgentMultisigDispatcher { contract_address }.add_signers(2, array![SIGNER_1(), SIGNER_2()]);
    IExternalRecoveryDispatcher { contract_address }.toggle_escape(true, 10, 10, GUARDIAN());
    (IExternalRecoveryDispatcher { contract_address }, IArgentMultisigDispatcher { contract_address })
}

// Toggle 

#[test]
fn test_toggle_escape() {
    let (component, _) = setup();
    let mut config = component.get_escape_enabled();
    assert!(config.is_enabled, "should be enabled");
    assert_eq!(config.security_period, 10, "should be 10");
    assert_eq!(config.expiry_period, 10, "should be 10");
    assert_eq!(component.get_guardian(), GUARDIAN(), "should be guardian");
    component.toggle_escape(false, 0, 0, contract_address_const::<0>());
    config = component.get_escape_enabled();
    assert_eq!(config.is_enabled, false, "should not be enabled");
    assert_eq!(config.security_period, 0, "should be 0");
    assert_eq!(config.expiry_period, 0, "should be 0");
    assert_eq!(component.get_guardian(), contract_address_const::<0>(), "guardian should be 0");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_toggle_unauthorised() {
    let (component, _) = setup();
    start_prank(CheatTarget::All, (contract_address_const::<42>()));
    component.toggle_escape(false, 0, 0, contract_address_const::<0>());
}

fn replace_signer_call(remove: Signer, replace_with: Signer) -> EscapeCall {
    EscapeCall { selector: selector!("replace_signer"), calldata: serialize(@(remove, replace_with)), }
}

// Trigger

#[test]
fn test_trigger_escape_replace_signer() {
    let (component, _) = setup();
    start_prank(CheatTarget::All, GUARDIAN());
    let call = replace_signer_call(SIGNER_1(), SIGNER_3());
    let call_hash = get_escape_call_hash(@call);
    component.trigger_escape(call);
    let (escape, status) = component.get_escape();
    assert_eq!(escape.call_hash, call_hash, "invalid call hash");
    assert_eq!(escape.ready_at, 10, "should be 10");
    assert_eq!(status, EscapeStatus::NotReady, "should be NotReady");
}

#[test]
fn test_trigger_escape_can_override() {
    let (component, _) = setup();
    start_prank(CheatTarget::All, GUARDIAN());

    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_4()));
    let second_call = replace_signer_call(SIGNER_1(), SIGNER_3());
    let second_call_hash = get_escape_call_hash(@second_call);
    component.trigger_escape(second_call);
    let (escape, _) = component.get_escape();
    assert_eq!(escape.call_hash, second_call_hash, "invalid call hash");
}

#[test]
#[should_panic(expected: ('argent/only-guardian',))]
fn test_trigger_escape_not_enabled() {
    let (component, _) = setup();
    component.toggle_escape(false, 0, 0, contract_address_const::<0>());
    start_prank(CheatTarget::All, GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_3()));
}

#[test]
#[should_panic(expected: ('argent/only-guardian',))]
fn test_trigger_escape_unauthorised() {
    let (component, _) = setup();
    start_prank(CheatTarget::All, contract_address_const::<42>());
    component.trigger_escape(replace_signer_call(SIGNER_1(), SIGNER_3()));
}

// Escape

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_NotReady() {
    let (component, _) = setup();
    start_prank(CheatTarget::One(component.contract_address), GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_warp(CheatTarget::All, 8);
    component.execute_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_Expired() {
    let (component, _) = setup();
    start_prank(CheatTarget::One(component.contract_address), GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_warp(CheatTarget::All, 28);
    component.execute_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
}

// Cancel

#[test]
fn test_cancel_escape() {
    let (component, multisig_component) = setup();
    start_prank(CheatTarget::All, GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_warp(CheatTarget::All, 11);
    start_prank(CheatTarget::All, component.contract_address);
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
    let (component, _) = setup();
    start_prank(CheatTarget::All, GUARDIAN());
    component.trigger_escape(replace_signer_call(SIGNER_2(), SIGNER_3()));
    start_warp(CheatTarget::All, 11);
    start_prank(CheatTarget::All, contract_address_const::<42>());
    component.cancel_escape();
}

