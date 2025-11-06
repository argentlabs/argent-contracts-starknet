use argent::multisig_account::signer_manager::{OwnerRemovedGuid, ThresholdUpdated, signer_manager_component};
use crate::{
    ITestArgentMultisigDispatcherTrait, MultisigSetup, SignerKeyPairImpl, StarknetKeyPair, initialize_multisig_m_of_n,
};
use snforge_std::{EventSpyAssertionsTrait, EventSpyTrait, spy_events};

#[test]
fn remove_signers_first() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    let mut spy = spy_events();

    // remove signer
    multisig.remove_signers(2, array![signers[0].signer()]);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 2);
    assert_eq!(multisig.get_threshold(), 2);
    assert!(!multisig.is_signer(signers[0].signer()));
    assert!(multisig.is_signer(signers[1].signer()));
    assert!(multisig.is_signer(signers[2].signer()));

    let removed_owner_guid = signers[0].into_guid();
    let event = signer_manager_component::Event::OwnerRemovedGuid(OwnerRemovedGuid { removed_owner_guid });
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    let event = signer_manager_component::Event::ThresholdUpdated(ThresholdUpdated { new_threshold: 2 });
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    assert_eq!(spy.get_events().events.len(), 2);
}

#[test]
fn remove_signers_center() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[1].signer()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 2);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[1].signer()));
    assert!(multisig.is_signer(signers[0].signer()));
    assert!(multisig.is_signer(signers[2].signer()));
}

#[test]
fn remove_signers_last() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[2].signer()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 2);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[2].signer()));
    assert!(multisig.is_signer(signers[0].signer()));
    assert!(multisig.is_signer(signers[1].signer()));
}

#[test]
fn remove_1_and_2() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[0].signer(), signers[1].signer()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[0].signer()));
    assert!(!multisig.is_signer(signers[1].signer()));
    assert!(multisig.is_signer(signers[2].signer()));
}

#[test]
fn remove_1_and_3() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[0].signer(), signers[2].signer()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[0].signer()));
    assert!(!multisig.is_signer(signers[2].signer()));
    assert!(multisig.is_signer(signers[1].signer()));
}

#[test]
fn remove_2_and_3() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[1].signer(), signers[2].signer()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[1].signer()));
    assert!(!multisig.is_signer(signers[2].signer()));
    assert!(multisig.is_signer(signers[0].signer()));
}

#[test]
fn remove_2_and_1() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[1].signer(), signers[0].signer()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[1].signer()));
    assert!(!multisig.is_signer(signers[0].signer()));
    assert!(multisig.is_signer(signers[2].signer()));
}

#[test]
fn remove_3_and_1() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[2].signer(), signers[0].signer()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[2].signer()));
    assert!(!multisig.is_signer(signers[0].signer()));
    assert!(multisig.is_signer(signers[1].signer()));
}

#[test]
fn remove_3_and_2() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[1].signer(), signers[2].signer()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[1].signer()));
    assert!(!multisig.is_signer(signers[2].signer()));
    assert!(multisig.is_signer(signers[0].signer()));
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn remove_invalid_signers() {
    // init
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![StarknetKeyPair::random().signer()];
    multisig.remove_signers(1, signer_to_remove);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn remove_same_signer_twice() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[1].signer(), signers[1].signer()];
    multisig.remove_signers(1, signer_to_remove);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn remove_signers_invalid_threshold() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[0].signer(), signers[1].signer()];
    multisig.remove_signers(2, signer_to_remove);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn remove_signers_zero_threshold() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // remove signer
    let signer_to_remove = array![signers[0].signer()];
    multisig.remove_signers(0, signer_to_remove);
}
