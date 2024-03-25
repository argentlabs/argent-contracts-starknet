use argent::multisig::multisig::{multisig_component};
use argent::presets::multisig_account::ArgentMultisigAccount;
use argent::signer::signer_signature::{
    Signer, StarknetSigner, SignerSignature, SignerTrait, starknet_signer_from_pubkey
};
use argent::signer_storage::signer_list::{signer_list_component};
use snforge_std::{ContractClassTrait, spy_events, SpyOn, EventSpy, EventFetcher, EventAssertions};
use super::setup::constants::{MULTISIG_OWNER};
use super::setup::multisig_test_setup::{
    initialize_multisig, ITestArgentMultisigDispatcherTrait, initialize_multisig_with,
    initialize_multisig_with_one_signer, declare_multisig
};

#[test]
fn add_signers() {
    // init
    let multisig = initialize_multisig_with_one_signer();
    let mut spy = spy_events(SpyOn::One(multisig.contract_address));

    // add signer
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    multisig.add_signers(2, array![signer_1]);

    // check 
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2, "invalid signers length");
    assert_eq!(multisig.get_threshold(), 2, "new threshold not set");

    spy.fetch_events();

    let events = array![
        (
            multisig.contract_address,
            signer_list_component::Event::OwnerAdded(
                signer_list_component::OwnerAdded { new_owner_guid: signer_1.into_guid() }
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

    let event = multisig_component::Event::ThresholdUpdated(multisig_component::ThresholdUpdated { new_threshold: 2 });
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    assert_eq!(spy.events.len(), 0, "excess events");
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
