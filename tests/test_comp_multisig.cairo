use argent::mocks::multisig_mocks::MultisigMock;
use argent::multisig_account::signer_manager::{
    ISignerManager, signer_manager_component, signer_manager_component::ISignerManagerInternal,
};
use argent::signer::signer_signature::SignerTrait;
use snforge_std::{start_cheat_caller_address_global, test_address};
use super::{SIGNER_1, SIGNER_2, SIGNER_3};

type ComponentState = signer_manager_component::ComponentState<MultisigMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    signer_manager_component::component_state_for_testing()
}

// Initialize

#[test]
fn test_initialize_3_signers() {
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);

    assert_eq!(component.get_threshold(), 2);
    assert!(component.is_signer(SIGNER_1()));
    assert!(component.is_signer(SIGNER_2()));
    assert!(component.is_signer(SIGNER_3()));
    let guids = component.get_signer_guids();
    assert_eq!(guids.len(), 3);
    assert_eq!(*guids.at(0), SIGNER_1().into_guid());
    assert_eq!(*guids.at(1), SIGNER_2().into_guid());
    assert_eq!(*guids.at(2), SIGNER_3().into_guid());
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
#[should_panic(expected: ('linked-set/already-in-set',))]
fn test_initialize_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_1(), SIGNER_2()]);
}

// Change threshold

#[test]
fn test_change_threshold() {
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    assert_eq!(component.get_threshold(), 2);
    start_cheat_caller_address_global(test_address());
    component.change_threshold(3);
    assert_eq!(component.get_threshold(), 3);
}

#[test]
#[should_panic(expected: ('argent/same-threshold',))]
fn test_change_threshold_same() {
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    assert_eq!(component.get_threshold(), 2);
    start_cheat_caller_address_global(test_address());
    component.change_threshold(2);
}

// Add signers

#[test]
fn test_add_1_signer_same_threshold() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2()]);
    assert_eq!(component.get_signer_guids().len(), 2);

    component.add_signers(2, array![SIGNER_3()]);
    assert_eq!(component.get_signer_guids().len(), 3);
    assert!(component.is_signer(SIGNER_3()));
}

#[test]
fn test_add_2_signers_same_threshold() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1()]);
    assert_eq!(component.get_signer_guids().len(), 1);

    component.add_signers(2, array![SIGNER_2(), SIGNER_3()]);
    assert_eq!(component.get_signer_guids().len(), 3);
    assert!(component.is_signer(SIGNER_2()));
    assert!(component.is_signer(SIGNER_3()));
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn test_add_1_signer_invalid_threshold() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![SIGNER_1(), SIGNER_2()]);
    component.add_signers(4, array![SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn test_initialize_add_duplicate_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1()]);
    component.add_signers(1, array![SIGNER_2(), SIGNER_2()]);
}

// Remove signers

#[test]
fn test_remove_first_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_1()]);
    assert_eq!(component.get_signer_guids().len(), 2);
    assert!(!component.is_signer(SIGNER_1()));
}

#[test]
fn test_remove_middle_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_2()]);
    assert_eq!(component.get_signer_guids().len(), 2);
    assert!(!component.is_signer(SIGNER_2()));
}

#[test]
fn test_remove_last_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_3()]);
    assert_eq!(component.get_signer_guids().len(), 2);
    assert!(!component.is_signer(SIGNER_3()));
}

#[test]
fn test_remove_2_signers() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_3(), SIGNER_1()]);
    assert_eq!(component.get_signer_guids().len(), 1);
    assert!(!component.is_signer(SIGNER_3()));
    assert!(!component.is_signer(SIGNER_1()));
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn test_remove_signer_invalid_threshold() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(3, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(3, array![SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn test_remove_all_signers() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(3, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
    component.remove_signers(1, array![SIGNER_1(), SIGNER_2(), SIGNER_3()]);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn test_remove_unknown_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.remove_signers(1, array![SIGNER_3()]);
}

// Replace signer

#[test]
fn test_replace_first_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.replace_signer(SIGNER_1(), SIGNER_3());
    assert_eq!(component.get_signer_guids().len(), 2);
    assert!(!component.is_signer(SIGNER_1()));
    assert!(component.is_signer(SIGNER_3()));
}

#[test]
fn test_replace_last_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.replace_signer(SIGNER_2(), SIGNER_3());
    assert_eq!(component.get_signer_guids().len(), 2);
    assert!(!component.is_signer(SIGNER_2()));
    assert!(component.is_signer(SIGNER_3()));
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn test_replace_unknown_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1()]);
    component.replace_signer(SIGNER_2(), SIGNER_3());
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn test_replace_duplicate_signer() {
    start_cheat_caller_address_global(test_address());
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![SIGNER_1(), SIGNER_2()]);
    component.replace_signer(SIGNER_2(), SIGNER_1());
}
