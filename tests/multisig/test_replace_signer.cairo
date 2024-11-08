use argent::multisig_account::signer_manager::signer_manager::signer_manager_component;
use argent::signer::signer_signature::{SignerTrait, starknet_signer_from_pubkey};
use argent::multisig_account::signer_storage::signer_list::signer_list_component;
use snforge_std::{spy_events, EventSpyAssertionsTrait, EventSpyTrait};
use super::super::{SIGNER_1, SIGNER_2, SIGNER_3, initialize_multisig_with, ITestArgentMultisigDispatcherTrait};

#[test]
fn replace_signer_1() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1()].span());

    // replace signer
    let signer_to_add = SIGNER_2();
    multisig.replace_signer(SIGNER_1(), signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(signer_to_add));
}

#[test]
fn replace_signer_start() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());
    let mut spy = spy_events();

    // replace signer
    let signer_to_add = starknet_signer_from_pubkey(5);
    multisig.replace_signer(SIGNER_1(), signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 3);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(signer_to_add));
    assert!(multisig.is_signer(SIGNER_2()));
    assert!(multisig.is_signer(SIGNER_3()));

    let events = array![
        (
            multisig.contract_address,
            signer_list_component::Event::OwnerRemovedGuid(
                signer_list_component::OwnerRemovedGuid { removed_owner_guid: SIGNER_1().into_guid() }
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

    assert_eq!(spy.get_events().events.len(), events.len());
}

#[test]
fn replace_signer_middle() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // replace signer
    let signer_to_add = starknet_signer_from_pubkey(5);
    multisig.replace_signer(SIGNER_2(), signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 3);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_2()));
    assert!(multisig.is_signer(signer_to_add));
    assert!(multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(SIGNER_3()));
}

#[test]
fn replace_signer_end() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // replace signer
    let signer_to_add = starknet_signer_from_pubkey(5);
    multisig.replace_signer(SIGNER_3(), signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 3);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(SIGNER_3()));
    assert!(multisig.is_signer(signer_to_add));
    assert!(multisig.is_signer(SIGNER_1()));
    assert!(multisig.is_signer(SIGNER_2()));
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn replace_invalid_signer() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // replace signer

    let signer_to_add = starknet_signer_from_pubkey(5);
    let not_a_signer = starknet_signer_from_pubkey(10);
    multisig.replace_signer(not_a_signer, signer_to_add);
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn replace_already_signer() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // replace signer
    multisig.replace_signer(SIGNER_3(), SIGNER_1());
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn replace_already_same_signer() {
    // init
    let multisig = initialize_multisig_with(threshold: 1, signers: array![SIGNER_1(), SIGNER_2(), SIGNER_3()].span());

    // replace signer
    multisig.replace_signer(SIGNER_1(), SIGNER_1());
}

