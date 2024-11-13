use argent::multisig_account::signer_manager::signer_manager::signer_manager_component;
use argent::multisig_account::signer_storage::signer_list::signer_list_component;
use argent::signer::signer_signature::{SignerTrait, starknet_signer_from_pubkey};
use snforge_std::{spy_events, EventSpyAssertionsTrait, EventSpyTrait};
use super::super::{
    SIGNER_1, SIGNER_2, SIGNER_3, initialize_multisig, initialize_multisig_with, ITestArgentMultisigDispatcherTrait
};

#[test]
fn remove_signers_first() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());
    let mut spy = spy_events();

    // remove signer
    multisig.remove_signers(2, array![SIGNER_1()]);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2);
    assert_eq!(multisig.get_threshold(), 2);
    assert!(!multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(SIGNER_2()));
    assert!(multisig.is_signer(SIGNER_3()));

    let removed_owner_guid = SIGNER_1().into_guid();
    let event = signer_list_component::Event::OwnerRemovedGuid(
        signer_list_component::OwnerRemovedGuid { removed_owner_guid }
    );
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    let event = signer_manager_component::Event::ThresholdUpdated(
        signer_manager_component::ThresholdUpdated { new_threshold: 2 }
    );
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    assert_eq!(spy.get_events().events.len(), 2);
}

#[test]
fn remove_signers_center() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_2()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_2()));
    assert!(multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(SIGNER_3()));
}

#[test]
fn remove_signers_last() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_3()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_3()));
    assert!(multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(SIGNER_2()));
}

#[test]
fn remove_1_and_2() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_1(), SIGNER_2()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_1()));
    assert!(!multisig.is_signer(SIGNER_2()));
    assert!(multisig.is_signer(SIGNER_3()));
}

#[test]
fn remove_1_and_3() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_1(), SIGNER_3()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_1()));
    assert!(!multisig.is_signer(SIGNER_3()));
    assert!(multisig.is_signer(SIGNER_2()));
}

#[test]
fn remove_2_and_3() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_2(), SIGNER_3()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_2()));
    assert!(!multisig.is_signer(SIGNER_3()));
    assert!(multisig.is_signer(SIGNER_1()));
}

#[test]
fn remove_2_and_1() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_2(), SIGNER_1()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_2()));
    assert!(!multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(SIGNER_3()));
}

#[test]
fn remove_3_and_1() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_3(), SIGNER_1()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_3()));
    assert!(!multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(SIGNER_2()));
}

#[test]
fn remove_3_and_2() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_2(), SIGNER_3()];
    multisig.remove_signers(1, signer_to_remove);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_3()));
    assert!(!multisig.is_signer(SIGNER_2()));
    assert!(multisig.is_signer(SIGNER_1()));
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn remove_invalid_signers() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![starknet_signer_from_pubkey(10)];
    multisig.remove_signers(1, signer_to_remove);
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn remove_same_signer_twice() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    multisig.remove_signers(1, array![SIGNER_2(), SIGNER_2()]);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn remove_signers_invalid_threshold() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // remove signer
    let signer_to_remove = array![SIGNER_1(), SIGNER_2()];
    multisig.remove_signers(2, signer_to_remove);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn remove_signers_zero_threshold() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    multisig.remove_signers(0, array![SIGNER_1()]);
}
