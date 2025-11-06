use argent::multisig_account::signer_manager::{ThresholdUpdated, signer_manager_component};
use crate::{
    ITestArgentMultisigDispatcherTrait, MultisigSetup, SignerKeyPairImpl, StarknetKeyPair, declare_multisig,
    initialize_multisig_m_of_n,
};
use snforge_std::{ContractClassTrait, EventSpyAssertionsTrait, EventSpyTrait, spy_events};

#[test]
fn valid_initialize() {
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(1, 1);
    let signer_1 = signers[0];
    assert_eq!(multisig.get_threshold(), 1);
    // test if is signer correctly returns true
    assert!(multisig.is_signer(signer_1.signer()));

    // test signers list
    let signers_guid = multisig.get_signer_guids();
    assert_eq!(signers_guid.len(), 1);
    assert_eq!(*signers_guid[0], signer_1.into_guid());
}

#[test]
fn valid_initialize_two_signers() {
    let threshold = 1;
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(threshold, 2);
    // test if is signer correctly returns true
    assert!(multisig.is_signer(signers[0].signer()));
    assert!(multisig.is_signer(signers[1].signer()));

    // test signers list
    let signers_guid = multisig.get_signer_guids();
    assert_eq!(signers_guid.len(), 2);
    assert_eq!(*signers_guid[0], signers[0].into_guid());
    assert_eq!(*signers_guid[1], signers[1].into_guid());
}

#[test]
fn invalid_threshold() {
    let threshold = 3;
    let signer_1 = StarknetKeyPair::random();
    let mut calldata = array![];
    threshold.serialize(ref calldata);
    array![signer_1.signer()].serialize(ref calldata);

    let argent_class = declare_multisig();
    argent_class.deploy(@calldata).expect_err('argent/bad-threshold');
}

#[test]
fn change_threshold() {
    let threshold = 1;
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(threshold, 2);
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
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);

    multisig.change_threshold(2);
}

#[test]
#[should_panic(expected: ('argent/invalid-threshold',))]
fn change_to_zero_threshold() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);

    multisig.change_threshold(0);
}

#[test]
fn get_name() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 3);
    assert_eq!(multisig.get_name(), 'ArgentMultisig');
}

#[test]
fn get_version() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 3);
    let version = multisig.get_version();
    assert_eq!(version.major, 0);
    assert_eq!(version.minor, 5);
    assert_eq!(version.patch, 0);
}

