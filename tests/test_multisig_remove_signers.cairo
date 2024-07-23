use argent::multisig::multisig::multisig_component;
use argent::signer::signer_signature::{SignerTrait, starknet_signer_from_pubkey};
use argent::signer_storage::signer_list::signer_list_component;
use snforge_std::{spy_events, EventSpyAssertionsTrait, EventSpyTrait};
use super::setup::constants::MULTISIG_OWNER;
use super::setup::multisig_test_setup::{
    initialize_multisig, initialize_multisig_with, ITestArgentMultisigDispatcherTrait
};

#[test]
fn remove_signers_first() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());
    let mut spy = spy_events();

    // remove signer
    multisig.remove_signers(2, array![signer_1]);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 2, "new threshold not set");
    assert!(!multisig.is_signer(signer_1), "signer 1 was not removed");
    assert!(multisig.is_signer(signer_2), "signer 2 was removed");
    assert!(multisig.is_signer(signer_3), "signer 3 was removed");

    let removed_owner_guid = signer_1.into_guid();
    let event = signer_list_component::Event::OwnerRemovedGuid(
        signer_list_component::OwnerRemovedGuid { removed_owner_guid }
    );
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    let event = multisig_component::Event::ThresholdUpdated(multisig_component::ThresholdUpdated { new_threshold: 2 });
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    assert_eq!(spy.get_events().events.len(), 2, "excess events");
}

#[test]
fn remove_signers_center() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_2];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 1, "new threshold not set");
    assert!(!multisig.is_signer(signer_2), "signer 2 was not removed");
    assert!(multisig.is_signer(signer_1), "signer 1 was removed");
    assert!(multisig.is_signer(signer_3), "signer 3 was removed");
}

#[test]
fn remove_signers_last() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 1, "new threshold not set");
    assert!(!multisig.is_signer(signer_3), "signer 3 was not removed");
    assert!(multisig.is_signer(signer_1), "signer 1 was removed");
    assert!(multisig.is_signer(signer_2), "signer 2 was removed");
}

#[test]
fn remove_1_and_2() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_1, signer_2];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 1, "new threshold not set");
    assert!(!multisig.is_signer(signer_1), "signer 1 was not removed");
    assert!(!multisig.is_signer(signer_2), "signer 2 was not removed");
    assert!(multisig.is_signer(signer_3), "signer 3 was removed");
}

#[test]
fn remove_1_and_3() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_1, signer_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 1, "new threshold not set");
    assert!(!multisig.is_signer(signer_1), "signer 1 was not removed");
    assert!(!multisig.is_signer(signer_3), "signer 3 was not removed");
    assert!(multisig.is_signer(signer_2), "signer 2 was removed");
}

#[test]
fn remove_2_and_3() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_2, signer_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 1, "new threshold not set");
    assert!(!multisig.is_signer(signer_2), "signer 2 was not removed");
    assert!(!multisig.is_signer(signer_3), "signer 3 was not removed");
    assert!(multisig.is_signer(signer_1), "signer 1 was removed");
}

#[test]
fn remove_2_and_1() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_2, signer_1];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 1, "new threshold not set");
    assert!(!multisig.is_signer(signer_2), "signer 2 was not removed");
    assert!(!multisig.is_signer(signer_1), "signer 1 was not removed");
    assert!(multisig.is_signer(signer_3), "signer 3 was removed");
}

#[test]
fn remove_3_and_1() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_3, signer_1];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 1, "new threshold not set");
    assert!(!multisig.is_signer(signer_3), "signer 3 was not removed");
    assert!(!multisig.is_signer(signer_1), "signer 1 was not removed");
    assert!(multisig.is_signer(signer_2), "signer 2 was removed");
}

#[test]
fn remove_3_and_2() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_2, signer_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 1, "new threshold not set");
    assert!(!multisig.is_signer(signer_3), "signer 3 was not removed");
    assert!(!multisig.is_signer(signer_2), "signer 2 was not removed");
    assert!(multisig.is_signer(signer_1), "signer 1 was removed");
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
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    multisig.remove_signers(1, array![signer_2, signer_2]);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn remove_signers_invalid_threshold() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_1, signer_2];
    multisig.remove_signers(2, signer_to_remove);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn remove_signers_zero_threshold() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    multisig.remove_signers(0, array![signer_1]);
}
