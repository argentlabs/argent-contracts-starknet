use argent::multiowner_account::events::SignerLinked;
use argent::multisig_account::signer_manager::{OwnerAddedGuid, ThresholdUpdated, signer_manager_component};
use argent::signer::signer_signature::{SignerTrait};
use crate::{
    ITestArgentMultisigDispatcherTrait, MultisigSetup, SignerKeyPairImpl, StarknetKeyPair, initialize_multisig_m_of_n,
};
use snforge_std::{EventSpyAssertionsTrait, EventSpyTrait, spy_events};

#[test]
fn add_signers() {
    // init
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);
    let mut spy = spy_events();

    // add signer
    let new_signer = StarknetKeyPair::random().signer();
    multisig.add_signers(2, array![new_signer]);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2);
    assert_eq!(multisig.get_threshold(), 2);

    let events = array![
        (
            multisig.contract_address,
            signer_manager_component::Event::OwnerAddedGuid(OwnerAddedGuid { new_owner_guid: new_signer.into_guid() }),
        ),
        (
            multisig.contract_address,
            signer_manager_component::Event::SignerLinked(
                SignerLinked { signer_guid: new_signer.into_guid(), signer: new_signer },
            ),
        ),
    ];
    spy.assert_emitted(@events);

    let event = signer_manager_component::Event::ThresholdUpdated(ThresholdUpdated { new_threshold: 2 });
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    assert_eq!(spy.get_events().events.len(), 3);
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn add_signer_already_in_list() {
    // init
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(2, 2);

    // add signer
    let new_signers = array![signers[0].signer()];
    multisig.add_signers(2, new_signers);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn add_signer_zero_threshold() {
    // init
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);

    // add signer
    let new_signers = array![StarknetKeyPair::random().signer()];
    multisig.add_signers(0, new_signers);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn add_signer_excessive_threshold() {
    // init
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);

    // add signer
    let new_signers = array![StarknetKeyPair::random().signer()];
    multisig.add_signers(3, new_signers);
}
