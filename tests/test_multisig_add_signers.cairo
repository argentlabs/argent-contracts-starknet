use argent::multisig::multisig::multisig_component;
use argent::signer::signer_signature::{SignerTrait, starknet_signer_from_pubkey};
use argent::signer_storage::signer_list::signer_list_component;
use snforge_std::{spy_events, EventSpyAssertionsTrait, EventSpyTrait};
use super::setup::{
    constants::MULTISIG_OWNER,
    multisig_test_setup::{ITestArgentMultisigDispatcherTrait, initialize_multisig_with_one_signer}
};
// TODO Update all assert_emitted to emitted_by()?

#[test]
fn add_signers() {
    // init
    let multisig = initialize_multisig_with_one_signer();
    let mut spy = spy_events();

    // add signer
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    multisig.add_signers(2, array![signer_1]);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 2, "new threshold not set");

    let events = array![
        (
            multisig.contract_address,
            signer_list_component::Event::OwnerAddedGuid(
                signer_list_component::OwnerAddedGuid { new_owner_guid: signer_1.into_guid() }
            )
        ),
        (
            multisig.contract_address,
            signer_list_component::Event::SignerLinked(
                signer_list_component::SignerLinked { signer_guid: signer_1.into_guid(), signer: signer_1 }
            )
        )
    ];
    spy.assert_emitted(@events);

    // TODO Is this correct?
    assert_eq!(spy.get_events().events.len(), 3, "excess events");
    let event = multisig_component::Event::ThresholdUpdated(multisig_component::ThresholdUpdated { new_threshold: 2 });
    spy.assert_emitted(@array![(multisig.contract_address, event)]);
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn add_signer_already_in_list() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey)];
    multisig.add_signers(2, new_signers);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn add_signer_zero_threshold() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey)];
    multisig.add_signers(0, new_signers);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn add_signer_excessive_threshold() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey)];
    multisig.add_signers(3, new_signers);
}
