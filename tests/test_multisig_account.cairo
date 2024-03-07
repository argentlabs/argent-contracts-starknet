use argent::presets::multisig_account::ArgentMultisigAccount;
use argent::signer::signer_signature::{
    Signer, StarknetSigner, SignerSignature, SignerTrait, starknet_signer_from_pubkey
};
use snforge_std::{get_class_hash, declare, ContractClass, ContractClassTrait};
use super::setup::constants::{MULTISIG_OWNER};
use super::setup::multisig_test_setup::{
    initialize_multisig, ITestArgentMultisigDispatcherTrait, initialize_multisig_with,
    initialize_multisig_with_one_signer, declare_multisig
};

#[test]
fn valid_initialize() {
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signers_array = array![signer_1];
    let multisig = initialize_multisig_with(threshold: 1, signers: signers_array.span());
    assert(multisig.get_threshold() == 1, 'threshold not set');
    // test if is signer correctly returns true
    assert(multisig.is_signer(signer_1), 'is signer cant find signer');

    // test signers list
    let signers_guid = multisig.get_signer_guids();
    assert(signers_guid.len() == 1, 'invalid signers length');
    assert(*signers_guid[0] == signer_1.into_guid(), 'invalid signers result');
}

#[test]
fn valid_initialize_two_signers() {
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let threshold = 1;
    let signers_array = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, signers_array.span());
    // test if is signer correctly returns true
    assert(multisig.is_signer(signer_1), 'is signer cant find signer 1');
    assert(multisig.is_signer(signer_2), 'is signer cant find signer 2');

    // test signers list
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 2, 'invalid signers length');
    assert(*signers[0] == signer_1.into_guid(), 'invalid signers result');
    assert(*signers[1] == signer_2.into_guid(), 'invalid signers result');
}

#[test]
fn invalid_threshold() {
    let threshold = 3;
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let mut calldata = array![];
    threshold.serialize(ref calldata);
    array![signer_1].serialize(ref calldata);

    let argent_class = declare_multisig();
    argent_class.deploy(@calldata).expect_err('argent/bad-threshold');
}

#[test]
fn change_threshold() {
    let threshold = 1;
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signers_array = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, signers_array.span());

    multisig.change_threshold(2);
    assert(multisig.get_threshold() == 2, 'new threshold not set');
}

#[test]
fn add_signers() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![starknet_signer_from_pubkey(MULTISIG_OWNER(2))];
    multisig.add_signers(2, new_signers);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 2, 'invalid signers length');
    assert(multisig.get_threshold() == 2, 'new threshold not set');
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn add_signer_already_in_list() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![starknet_signer_from_pubkey(MULTISIG_OWNER(1))];
    multisig.add_signers(2, new_signers);
}

#[test]
fn get_name() {
    assert(initialize_multisig().get_name() == 'ArgentMultisig', 'Name should be ArgentMultisig');
}

#[test]
fn get_version() {
    let version = initialize_multisig().get_version();
    assert(version.major == 0, 'Version major');
    assert(version.minor == 2, 'Version minor');
    assert(version.patch == 0, 'Version patch');
}

