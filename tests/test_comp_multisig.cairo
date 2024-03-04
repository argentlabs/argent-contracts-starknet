use argent::mocks::multisig_mocks::MultisigMock;
use argent::multisig::interface::IArgentMultisig;
use argent::multisig::interface::IArgentMultisigInternal;
use argent::multisig::{multisig::multisig_component};
use argent::signer::{signer_signature::{Signer, StarknetSigner, starknet_signer_from_pubkey, SignerTrait}};
use argent::signer_storage::signer_list::signer_list_component;
use snforge_std::{start_prank, CheatTarget, test_address};
use super::setup::constants::{MULTISIG_OWNER};

type ComponentState = multisig_component::ComponentState<MultisigMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    multisig_component::component_state_for_testing()
}

fn SIGNER_1() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(1))
}

fn SIGNER_2() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(2))
}

fn SIGNER_3() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(3))
}

// Initialize

#[test]
fn test_initialize_3_signers() {
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);

    assert(component.get_threshold() == 2, 'wrong threshold');
    assert(component.is_signer(SIGNER_1()), 'should be signer');
    assert(component.is_signer(SIGNER_2()), 'should be signer');
    assert(component.is_signer(SIGNER_3()), 'should be signer');
    let guids = component.get_signer_guids();
    assert(guids.len() == 3, 'wrong signer length');
    assert(*guids.at(0) == SIGNER_1().into_guid(), 'should be signer 0');
    assert(*guids.at(1) == SIGNER_2().into_guid(), 'should be signer 0');
    assert(*guids.at(2) == SIGNER_3().into_guid(), 'should be signer 0');
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn test_initialize_threshold_zero() {
    let mut component = COMPONENT_STATE();
    component.initialize(0, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn test_initialize_threshold_larger_then_signers() {
    let mut component = COMPONENT_STATE();
    component.initialize(7, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn test_initialize_no_signers() {
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![]);
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn test_initialize_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_1(), SIGNER_2()]);
}

// Change threshold

#[test]
fn test_change_threshold() {
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    assert(component.get_threshold() == 2, 'wrong threshold');
    start_prank(CheatTarget::All, test_address());
    component.change_threshold(3);
    assert(component.get_threshold() == 3, 'wrong threshold');
}

#[test]
#[should_panic(expected: ('argent/same-threshold',))]
fn test_change_threshold_same() {
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    assert(component.get_threshold() == 2, 'wrong threshold');
    start_prank(CheatTarget::All, test_address());
    component.change_threshold(2);
}

// Add signers 

#[test]
fn test_add_1_signer_same_threshold() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2()]);
    assert(component.get_signer_guids().len() == 2, 'wrong signer length');

    component.add_signers(2, array![SIGNER_3()]);
    assert(component.get_signer_guids().len() == 3, 'wrong signer length');
    assert(component.is_signer(SIGNER_3()), 'should be signer');
}

#[test]
fn test_add_2_signers_same_threshold() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1()]);
    assert(component.get_signer_guids().len() == 1, 'wrong signer length');

    component.add_signers(2, array![SIGNER_2(), SIGNER_3()]);
    assert(component.get_signer_guids().len() == 3, 'wrong signer length');
    assert(component.is_signer(SIGNER_2()), 'should be signer');
    assert(component.is_signer(SIGNER_3()), 'should be signer');
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn test_add_1_signer_invalid_threshold() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2()]);
    component.add_signers(4, array![SIGNER_3()]);
}

// Remove signers

#[test]
fn test_remove_first_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_1()]);
    assert(component.get_signer_guids().len() == 2, 'wrong signer length');
    assert(!component.is_signer(SIGNER_1()), 'should not be signer');
}

#[test]
fn test_remove_middle_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_2()]);
    assert(component.get_signer_guids().len() == 2, 'wrong signer length');
    assert(!component.is_signer(SIGNER_2()), 'should not be signer');
}

#[test]
fn test_remove_last_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_3()]);
    assert(component.get_signer_guids().len() == 2, 'wrong signer length');
    assert(!component.is_signer(SIGNER_3()), 'should not be signer');
}

#[test]
fn test_remove_2_signers() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_3(), SIGNER_1()]);
    assert(component.get_signer_guids().len() == 1, 'wrong signer length');
    assert(!component.is_signer(SIGNER_3()), 'should not be signer');
    assert(!component.is_signer(SIGNER_1()), 'should not be signer');
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn test_remove_signer_invalid_threshold() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(3, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(3, array![SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn test_remove_all_signers() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(3, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_remove_unknown_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.remove_signers(1, array![SIGNER_3()]);
}

// Replace signer

#[test]
fn test_replace_first_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.replace_signer(SIGNER_1(), SIGNER_3());
    assert(component.get_signer_guids().len() == 2, 'wrong signer length');
    assert(!component.is_signer(SIGNER_1()), 'should not be signer');
    assert(component.is_signer(SIGNER_3()), 'should be signer');
}

#[test]
fn test_replace_last_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.replace_signer(SIGNER_2(), SIGNER_3());
    assert(component.get_signer_guids().len() == 2, 'wrong signer length');
    assert(!component.is_signer(SIGNER_2()), 'should not be signer');
    assert(component.is_signer(SIGNER_3()), 'should be signer');
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_replace_unknown_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1()]);
    component.replace_signer(SIGNER_2(), SIGNER_3());
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn test_replace_duplicate_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.replace_signer(SIGNER_2(), SIGNER_1());
}

// Reorder signers

#[test]
fn test_reorder_all_signers() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(3, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.reorder_signers(array![SIGNER_2(), SIGNER_3(), SIGNER_1()]);
    let guids = component.get_signer_guids();
    assert(*guids.at(0) == SIGNER_2().into_guid(), 'should be signer 0');
    assert(*guids.at(1) == SIGNER_3().into_guid(), 'should be signer 1');
    assert(*guids.at(2) == SIGNER_1().into_guid(), 'should be signer 2');
}

#[test]
fn test_reorder_2_signers() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.reorder_signers(array![SIGNER_1(), SIGNER_3(), SIGNER_2()]);
    let guids = component.get_signer_guids();
    assert(*guids.at(0) == SIGNER_1().into_guid(), 'should be signer 0');
    assert(*guids.at(1) == SIGNER_3().into_guid(), 'should be signer 1');
    assert(*guids.at(2) == SIGNER_2().into_guid(), 'should be signer 2');
}

#[test]
#[should_panic(expected: ('argent/too-short',))]
fn test_reorder_wrong_length() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.reorder_signers(array![SIGNER_2(), SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_reorder_unknown_signer() {
    start_prank(CheatTarget::All, test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.reorder_signers(array![SIGNER_2(), SIGNER_3()]);
}

