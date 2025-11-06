use argent::multisig_account::signer_manager::{
    ISignerManager, signer_manager_component, signer_manager_component::ISignerManagerInternal,
};
use argent::signer::signer_signature::{Signer, SignerTrait};
use crate::StarknetKeyPair;
use snforge_std::{start_cheat_caller_address_global, test_address};


#[starknet::contract]
pub mod MultisigMock {
    use argent::multisig_account::signer_manager::signer_manager_component;

    component!(path: signer_manager_component, storage: signer_manager, event: SignerManagerEvents);
    impl SignerManager = signer_manager_component::SignerManagerImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_manager: signer_manager_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SignerManagerEvents: signer_manager_component::Event,
    }
}

type ComponentState = signer_manager_component::ComponentState<MultisigMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    start_cheat_caller_address_global(test_address());
    signer_manager_component::component_state_for_testing()
}

struct CompMultisigSetup {
    signers: Span<Signer>,
    component: ComponentState,
}

fn initialize_with_3_signers() -> CompMultisigSetup {
    let mut component = COMPONENT_STATE();
    let signers = array![
        StarknetKeyPair::random().signer(), StarknetKeyPair::random().signer(), StarknetKeyPair::random().signer(),
    ];
    component.initialize(2, signers.clone());
    CompMultisigSetup { signers: signers.span(), component }
}

// Initialize

#[test]
fn test_initialize_3_signers() {
    let mut component = COMPONENT_STATE();
    let signer_1 = StarknetKeyPair::random().signer();
    let signer_2 = StarknetKeyPair::random().signer();
    let signer_3 = StarknetKeyPair::random().signer();
    component.initialize(2, array![signer_1, signer_2, signer_3]);

    assert_eq!(component.get_threshold(), 2);
    assert!(component.is_signer(signer_1));
    assert!(component.is_signer(signer_2));
    assert!(component.is_signer(signer_3));
    let guids = component.get_signer_guids();
    assert_eq!(guids.len(), 3);
    assert_eq!(*guids.at(0), signer_1.into_guid());
    assert_eq!(*guids.at(1), signer_2.into_guid());
    assert_eq!(*guids.at(2), signer_3.into_guid());
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn test_initialize_threshold_zero() {
    let mut component = COMPONENT_STATE();
    component
        .initialize(
            0,
            array![
                StarknetKeyPair::random().signer(),
                StarknetKeyPair::random().signer(),
                StarknetKeyPair::random().signer(),
            ],
        );
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn test_initialize_threshold_larger_then_signers() {
    let mut component = COMPONENT_STATE();
    component
        .initialize(
            7,
            array![
                StarknetKeyPair::random().signer(),
                StarknetKeyPair::random().signer(),
                StarknetKeyPair::random().signer(),
            ],
        );
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
    let signer_1 = StarknetKeyPair::random().signer();
    component.initialize(1, array![signer_1, signer_1, StarknetKeyPair::random().signer()]);
}

// Change threshold

#[test]
fn test_change_threshold() {
    let CompMultisigSetup { mut component, .. } = initialize_with_3_signers();
    assert_eq!(component.get_threshold(), 2);
    component.change_threshold(3);
    assert_eq!(component.get_threshold(), 3);
}

#[test]
#[should_panic(expected: ('argent/same-threshold',))]
fn test_change_threshold_same() {
    let CompMultisigSetup { mut component, .. } = initialize_with_3_signers();
    assert_eq!(component.get_threshold(), 2);
    component.change_threshold(2);
}

// Add signers

#[test]
fn test_add_1_signer_same_threshold() {
    let CompMultisigSetup { mut component, .. } = initialize_with_3_signers();
    assert_eq!(component.get_signer_guids().len(), 3);

    let new_signer = StarknetKeyPair::random().signer();
    component.add_signers(1, array![new_signer]);
    assert_eq!(component.get_signer_guids().len(), 4);
    assert!(component.is_signer(new_signer));
}

#[test]
fn test_add_2_signers_same_threshold() {
    let mut component = COMPONENT_STATE();
    let signer_1 = StarknetKeyPair::random().signer();
    let signer_2 = StarknetKeyPair::random().signer();
    component.initialize(1, array![signer_1]);
    assert_eq!(component.get_signer_guids().len(), 1);

    let signer_3 = StarknetKeyPair::random().signer();
    component.add_signers(2, array![signer_2, signer_3]);
    assert_eq!(component.get_signer_guids().len(), 3);
    assert!(component.is_signer(signer_2));
    assert!(component.is_signer(signer_3));
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn test_add_1_signer_invalid_threshold() {
    let mut component = COMPONENT_STATE();
    component.initialize(2, array![StarknetKeyPair::random().signer(), StarknetKeyPair::random().signer()]);
    component.add_signers(4, array![StarknetKeyPair::random().signer()]);
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn test_initialize_add_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component.initialize(1, array![StarknetKeyPair::random().signer()]);
    let new_signer = StarknetKeyPair::random().signer();
    component.add_signers(1, array![new_signer, new_signer]);
}

// Remove signers

#[test]
fn test_remove_first_signer() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    component.remove_signers(1, array![*signers[0]]);
    assert_eq!(component.get_signer_guids().len(), 2);
    assert!(!component.is_signer(*signers[0]));
}

#[test]
fn test_remove_middle_signer() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    component.remove_signers(1, array![*signers[1]]);
    assert_eq!(component.get_signer_guids().len(), 2);
    assert!(!component.is_signer(*signers[1]));
}

#[test]
fn test_remove_last_signer() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    component.remove_signers(1, array![*signers[2]]);
    assert_eq!(component.get_signer_guids().len(), 2);
    assert!(!component.is_signer(*signers[2]));
}

#[test]
fn test_remove_2_signers() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    component.remove_signers(1, array![*signers[2], *signers[0]]);
    assert_eq!(component.get_signer_guids().len(), 1);
    assert!(!component.is_signer(*signers[2]));
    assert!(!component.is_signer(*signers[0]));
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn test_remove_signer_invalid_threshold() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    component.remove_signers(3, array![*signers[2]]);
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn test_remove_all_signers() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    component.remove_signers(1, array![*signers[0], *signers[1], *signers[2]]);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn test_remove_unknown_signer() {
    let CompMultisigSetup { mut component, .. } = initialize_with_3_signers();
    component.remove_signers(1, array![StarknetKeyPair::random().signer()]);
}

// Replace signer

#[test]
fn test_replace_first_signer() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    let new_signer = StarknetKeyPair::random().signer();
    component.replace_signer(*signers[0], new_signer);
    assert_eq!(component.get_signer_guids().len(), 3);
    assert!(!component.is_signer(*signers[0]));
    assert!(component.is_signer(new_signer));
}

#[test]
fn test_replace_last_signer() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    let new_signer = StarknetKeyPair::random().signer();
    component.replace_signer(*signers[2], new_signer);
    assert_eq!(component.get_signer_guids().len(), 3);
    assert!(!component.is_signer(*signers[2]));
    assert!(component.is_signer(new_signer));
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn test_replace_unknown_signer() {
    let CompMultisigSetup { mut component, .. } = initialize_with_3_signers();
    component.replace_signer(StarknetKeyPair::random().signer(), StarknetKeyPair::random().signer());
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn test_replace_duplicate_signer() {
    let CompMultisigSetup { mut component, signers } = initialize_with_3_signers();
    component.replace_signer(*signers[1], *signers[0]);
}
