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
fn valid_initialize() {
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signers_array = array![signer_1];
    let multisig = initialize_multisig_with(threshold: 1, signers: signers_array.span());
    assert_eq!(multisig.get_threshold(), 1, "threshold not set");
    // test if is signer correctly returns true
    assert!(multisig.is_signer(signer_1), "is signer cant find signer");

    // test signers list
    let signers_guid = multisig.get_signer_guids();
    assert_eq!(signers_guid.len(), 1, "invalid signers length");
    assert_eq!(*signers_guid[0], signer_1.into_guid(), "invalid signers result");
}

#[test]
fn valid_initialize_two_signers() {
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let threshold = 1;
    let signers_array = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, signers_array.span());
    // test if is signer correctly returns true
    assert!(multisig.is_signer(signer_1), "is signer cant find signer 1");
    assert!(multisig.is_signer(signer_2), "is signer cant find signer 2");

    // test signers list
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2, "invalid signers length");
    assert_eq!(*signers[0], signer_1.into_guid(), "invalid signers result");
    assert_eq!(*signers[1], signer_2.into_guid(), "invalid signers result");
}

#[test]
fn invalid_threshold() {
    let threshold = 3;
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let mut calldata = array![];
    threshold.serialize(ref calldata);
    array![signer_1].serialize(ref calldata);

    let argent_class = declare_multisig();
    argent_class.deploy(@calldata).expect_err('argent/bad-threshold');
}

#[test]
fn change_threshold() {
    let threshold = 1;
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let signers_array = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, signers_array.span());
    let mut spy = spy_events(SpyOn::One(multisig.contract_address));

    multisig.change_threshold(2);
    assert_eq!(multisig.get_threshold(), 2, "new threshold not set");

    let event = multisig_component::Event::ThresholdUpdated(multisig_component::ThresholdUpdated { new_threshold: 2 });
    spy.assert_emitted(@array![(multisig.contract_address, event)]);

    assert_eq!(spy.events.len(), 0, "excess events");
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn change_to_excessive_threshold() {
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1].span());

    multisig.change_threshold(2);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn change_to_zero_threshold() {
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1].span());

    multisig.change_threshold(0);
}

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
fn get_name() {
    assert_eq!(initialize_multisig().get_name(), 'ArgentMultisig', "Name should be ArgentMultisig");
}

#[test]
fn get_version() {
    let version = initialize_multisig().get_version();
    assert_eq!(version.major, 0, "Version major");
    assert_eq!(version.minor, 2, "Version minor");
    assert_eq!(version.patch, 0, "Version patch");
}

