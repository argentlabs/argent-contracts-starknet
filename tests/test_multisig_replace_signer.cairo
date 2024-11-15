use argent::multisig::multisig::multisig_component;
use argent::signer::signer_signature::{SignerTrait, starknet_signer_from_pubkey};
use argent::signer_storage::signer_list::signer_list_component;
use snforge_std::{spy_events, EventSpyAssertionsTrait, EventSpyTrait};
use super::setup::constants::MULTISIG_OWNER;
use super::setup::multisig_test_setup::{initialize_multisig_with, ITestArgentMultisigDispatcherTrait};

#[test]
fn replace_signer_1() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1].span());

    // replace signer
    let signer_to_add = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    multisig.replace_signer(signer_1, signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1, "signer list changed size");
    assert_eq!(multisig.get_threshold(), 1, "threshold changed");
    assert!(!multisig.is_signer(signer_1), "signer 1 was not removed");
    assert!(multisig.is_signer(signer_to_add), "new was not added");
}

#[test]
fn replace_signer_start() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());
    let mut spy = spy_events();

    // replace signer
    let signer_to_add = starknet_signer_from_pubkey(5);
    multisig.replace_signer(signer_1, signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 3, "signer list changed size");
    assert_eq!(multisig.get_threshold(), 1, "threshold changed");
    assert!(!multisig.is_signer(signer_1), "signer 1 was not removed");
    assert!(multisig.is_signer(signer_to_add), "new was not added");
    assert!(multisig.is_signer(signer_2), "signer 2 was removed");
    assert!(multisig.is_signer(signer_3), "signer 3 was removed");

    let events = array![
        (
            multisig.contract_address,
            signer_list_component::Event::OwnerRemovedGuid(
                signer_list_component::OwnerRemovedGuid { removed_owner_guid: signer_1.into_guid() }
            )
        ),
        (
            multisig.contract_address,
            signer_list_component::Event::OwnerAddedGuid(
                signer_list_component::OwnerAddedGuid { new_owner_guid: signer_to_add.into_guid() }
            )
        ),
        (
            multisig.contract_address,
            signer_list_component::Event::SignerLinked(
                signer_list_component::SignerLinked { signer_guid: signer_to_add.into_guid(), signer: signer_to_add }
            )
        )
    ];
    spy.assert_emitted(@events);

    assert_eq!(spy.get_events().events.len(), events.len(), "excess events");
}

#[test]
fn replace_signer_middle() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // replace signer
    let signer_to_add = starknet_signer_from_pubkey(5);
    multisig.replace_signer(signer_2, signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 3, "signer list changed size");
    assert_eq!(multisig.get_threshold(), 1, "threshold changed");
    assert!(!multisig.is_signer(signer_2), "signer 2 was not removed");
    assert!(multisig.is_signer(signer_to_add), "new was not added");
    assert!(multisig.is_signer(signer_1), "signer 1 was removed");
    assert!(multisig.is_signer(signer_3), "signer 3 was removed");
}

#[test]
fn replace_signer_end() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // replace signer
    let signer_to_add = starknet_signer_from_pubkey(5);
    multisig.replace_signer(signer_3, signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 3, "signer list changed size");
    assert_eq!(multisig.get_threshold(), 1, "threshold changed");
    assert!(!multisig.is_signer(signer_3), "signer 3 was not removed");
    assert!(multisig.is_signer(signer_to_add), "new was not added");
    assert!(multisig.is_signer(signer_1), "signer 1 was removed");
    assert!(multisig.is_signer(signer_2), "signer 2 was removed");
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn replace_invalid_signer() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // replace signer

    let signer_to_add = starknet_signer_from_pubkey(5);
    let not_a_signer = starknet_signer_from_pubkey(10);
    multisig.replace_signer(not_a_signer, signer_to_add);
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn replace_already_signer() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // replace signer
    multisig.replace_signer(signer_3, signer_1);
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn replace_already_same_signer() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // replace signer
    multisig.replace_signer(signer_1, signer_1);
}

