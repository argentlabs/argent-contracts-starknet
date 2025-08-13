use argent::multisig_account::signer_manager::{ThresholdUpdated, signer_manager_component};
use argent::signer::signer_signature::{SignerTrait};
use crate::{
    ITestArgentMultisigDispatcherTrait, SIGNER_1, SIGNER_2, declare_multisig, initialize_multisig,
    initialize_multisig_with,
};
use snforge_std::{ContractClassTrait, EventSpyAssertionsTrait, EventSpyTrait, spy_events};

#[test]
fn valid_initialize() {
    let signer_1 = SIGNER_1();
    let signers_array = array![signer_1];
    let multisig = initialize_multisig_with(threshold: 1, signers: signers_array.span());
    assert_eq!(multisig.get_threshold(), 1);
    // test if is signer correctly returns true
    assert!(multisig.is_signer(signer_1));

    // test signers list
    let signers_guid = multisig.get_signer_guids();
    assert_eq!(signers_guid.len(), 1);
    assert_eq!(*signers_guid[0], signer_1.into_guid());
}

#[test]
fn valid_initialize_two_signers() {
    let signer_1 = SIGNER_1();
    let signer_2 = SIGNER_2();
    let threshold = 1;
    let signers_array = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, signers_array.span());
    // test if is signer correctly returns true
    assert!(multisig.is_signer(signer_1));
    assert!(multisig.is_signer(signer_2));

    // test signers list
    let signers = multisig.get_signer_guids();
    assert_eq!(signers.len(), 2);
    assert_eq!(*signers[0], signer_1.into_guid());
    assert_eq!(*signers[1], signer_2.into_guid());
}

#[test]
fn invalid_threshold() {
    let threshold = 3;
    let signer_1 = SIGNER_1();
    let mut calldata = array![];
    threshold.serialize(ref calldata);
    array![signer_1].serialize(ref calldata);

    let argent_class = declare_multisig();
    argent_class.deploy(@calldata).expect_err('argent/bad-threshold');
}

#[test]
fn change_threshold() {
    let threshold = 1;
    let signer_1 = SIGNER_1();
    let signer_2 = SIGNER_2();
    let signers_array = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, signers_array.span());
    let mut spy = spy_events();

    multisig.change_threshold(2);
    assert_eq!(multisig.get_threshold(), 2);

    let event = signer_manager_component::Event::ThresholdUpdated(ThresholdUpdated { new_threshold: 2 });
    spy.assert_emitted(@array![(multisig.contract_address, event)]);
    assert_eq!(spy.get_events().events.len(), 1);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn change_to_excessive_threshold() {
    let signer_1 = SIGNER_1();
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1].span());

    multisig.change_threshold(2);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn change_to_zero_threshold() {
    let signer_1 = SIGNER_1();
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1].span());

    multisig.change_threshold(0);
}

#[test]
fn get_name() {
    assert_eq!(initialize_multisig().get_name(), 'ArgentMultisig');
}

#[test]
fn get_version() {
    let version = initialize_multisig().get_version();
    assert_eq!(version.major, 0);
    assert_eq!(version.minor, 5);
    assert_eq!(version.patch, 0);
}

