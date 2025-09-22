use argent::multiowner_account::events::SignerLinked;
use argent::multisig_account::signer_manager::{OwnerAddedGuid, OwnerRemovedGuid, signer_manager_component};
use argent::signer::signer_signature::{SignerTrait};
use crate::{
    ITestArgentMultisigDispatcherTrait, MultisigSetup, SignerKeyPairImpl, StarknetKeyPair, initialize_multisig_m_of_n,
};
use snforge_std::{EventSpyAssertionsTrait, EventSpyTrait, spy_events};

#[test]
fn replace_signer_1() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 1);
    let signer_1 = signers[0].signer();

    // replace signer
    let signer_to_add = StarknetKeyPair::random().signer();
    multisig.replace_signer(signer_1, signer_to_add);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 1);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signer_1));
    assert!(multisig.is_signer(signer_to_add));
}

#[test]
fn replace_signer_start() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);
    let mut spy = spy_events();
    let signer_1 = signers[0].signer();

    // replace signer
    let signer_to_add = StarknetKeyPair::random().signer();
    multisig.replace_signer(signer_1, signer_to_add);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 3);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signer_1));
    assert!(multisig.is_signer(signer_to_add));
    assert!(multisig.is_signer(signers[1].signer()));
    assert!(multisig.is_signer(signers[2].signer()));

    let events = array![
        (
            multisig.contract_address,
            signer_manager_component::Event::OwnerRemovedGuid(
                OwnerRemovedGuid { removed_owner_guid: signer_1.into_guid() },
            ),
        ),
        (
            multisig.contract_address,
            signer_manager_component::Event::OwnerAddedGuid(
                OwnerAddedGuid { new_owner_guid: signer_to_add.into_guid() },
            ),
        ),
        (
            multisig.contract_address,
            signer_manager_component::Event::SignerLinked(
                SignerLinked { signer_guid: signer_to_add.into_guid(), signer: signer_to_add },
            ),
        ),
    ];
    spy.assert_emitted(@events);

    assert_eq!(spy.get_events().events.len(), events.len());
}

#[test]
fn replace_signer_middle() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // replace signer
    let signer_to_add = StarknetKeyPair::random().signer();
    multisig.replace_signer(signers[1].signer(), signer_to_add);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 3);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[1].signer()));
    assert!(multisig.is_signer(signer_to_add));
    assert!(multisig.is_signer(signers[0].signer()));
    assert!(multisig.is_signer(signers[2].signer()));
}

#[test]
fn replace_signer_end() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 3);

    // replace signer
    let signer_to_add = StarknetKeyPair::random().signer();
    multisig.replace_signer(signers[2].signer(), signer_to_add);

    // check
    let signers_guids = multisig.get_signer_guids();
    assert_eq!(signers_guids.len(), 3);
    assert_eq!(multisig.get_threshold(), 1);
    assert!(!multisig.is_signer(signers[2].signer()));
    assert!(multisig.is_signer(signer_to_add));
    assert!(multisig.is_signer(signers[0].signer()));
    assert!(multisig.is_signer(signers[1].signer()));
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn replace_invalid_signer_with_existing_one() {
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 1);
    let not_a_signer = StarknetKeyPair::random().signer();
    multisig.replace_signer(not_a_signer, signers[0].signer());
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn replace_invalid_signer_with_valid_one() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);
    let not_a_signer_1 = StarknetKeyPair::random().signer();
    let not_a_signer_2 = StarknetKeyPair::random().signer();
    multisig.replace_signer(not_a_signer_1, not_a_signer_2);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn replace_invalid_signer_with_the_same_signer() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);
    let not_a_signer = StarknetKeyPair::random().signer();
    multisig.replace_signer(not_a_signer, not_a_signer);
}

#[test]
#[should_panic(expected: ('argent/replace-same-signer',))]
fn replace_valid_signer_with_same() {
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 1);
    multisig.replace_signer(signers[0].signer(), signers[0].signer());
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn replace_valid_signer_with_existing_one() {
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 2);
    multisig.replace_signer(signers[0].signer(), signers[1].signer());
}
