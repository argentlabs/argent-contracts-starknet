use argent::multisig_account::signer_manager::signer_manager::signer_manager_component;
use argent::signer::signer_signature::{SignerTrait};
use snforge_std::{spy_events, EventSpyAssertionsTrait, EventSpyTrait};
use super::super::{SIGNER_1, SIGNER_2, ITestArgentMultisigDispatcherTrait, initialize_multisig_with_one_signer};

#[test]
fn add_signers() {
    // init
    let multisig = initialize_multisig_with_one_signer();
    let mut spy = spy_events();

    // add signer
    let signer_1 = SIGNER_2();
    multisig.add_signers(2, array![signer_1]);

    // check
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2);
    assert_eq!(multisig.get_threshold(), 2);

    let events = array![
        (
            multisig.contract_address,
            signer_manager_component::Event::OwnerAddedGuid(
                signer_manager_component::OwnerAddedGuid { new_owner_guid: signer_1.into_guid() }
            )
        ),
        (
            multisig.contract_address,
            signer_manager_component::Event::SignerLinked(
                signer_manager_component::SignerLinked { signer_guid: signer_1.into_guid(), signer: signer_1 }
            )
        )
    ];
    spy.assert_emitted(@events);

    let event = signer_manager_component::Event::ThresholdUpdated(
        signer_manager_component::ThresholdUpdated { new_threshold: 2 }
    );
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    assert_eq!(spy.get_events().events.len(), 3);
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn add_signer_already_in_list() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![SIGNER_1()];
    multisig.add_signers(2, new_signers);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn add_signer_zero_threshold() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![SIGNER_2()];
    multisig.add_signers(0, new_signers);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn add_signer_excessive_threshold() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![SIGNER_2()];
    multisig.add_signers(3, new_signers);
}
