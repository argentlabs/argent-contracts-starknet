use argent::common::signer_signature::IntoGuid;
use argent::common::signer_signature::{Signer, StarknetSigner, SignerSignature};
use argent::multisig::argent_multisig::ArgentMultisig;
use argent_tests::setup::multisig_test_setup::{
    initialize_multisig, signer_pubkey_1, signer_pubkey_2, ITestArgentMultisigDispatcherTrait, initialize_multisig_with,
    initialize_multisig_with_one_signer
};
use core::serde::Serde;
use starknet::deploy_syscall;

#[test]
#[available_gas(20000000)]
fn valid_initialize() {
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signers_array = array![signer_1];
    let multisig = initialize_multisig_with(threshold: 1, signers: signers_array.span());
    assert(multisig.get_threshold() == 1, 'threshold not set');
    // test if is signer correctly returns true
    assert(multisig.is_signer(signer_1), 'is signer cant find signer');

    // test signers list
    let signers_guid = multisig.get_signers_guid();
    assert(signers_guid.len() == 1, 'invalid signers length');
    assert(*signers_guid[0] == signer_1.into_guid().unwrap(), 'invalid signers result');
}

#[test]
#[available_gas(20000000)]
fn valid_initialize_two_signers() {
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let threshold = 1;
    let signers_array = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, signers_array.span());
    // test if is signer correctly returns true
    assert(multisig.is_signer(signer_1), 'is signer cant find signer 1');
    assert(multisig.is_signer(signer_2), 'is signer cant find signer 2');

    // test signers list
    let signers = multisig.get_signers_guid();
    assert(signers.len() == 2, 'invalid signers length');
    assert(*signers[0] == signer_1.into_guid().unwrap(), 'invalid signers result');
    assert(*signers[1] == signer_2.into_guid().unwrap(), 'invalid signers result');
}

#[test]
#[available_gas(20000000)]
fn invalid_threshold() {
    let threshold = 3;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let mut calldata = array![];
    threshold.serialize(ref calldata);
    array![signer_1].serialize(ref calldata);

    let class_hash = ArgentMultisig::TEST_CLASS_HASH.try_into().unwrap();
    let mut err = deploy_syscall(class_hash, 0, calldata.span(), true).unwrap_err();
    assert(@err.pop_front().unwrap() == @'argent/bad-threshold', 'Should be argent/bad-threshold');
}

#[test]
#[available_gas(20000000)]
fn change_threshold() {
    let threshold = 1;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let signers_array = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, signers_array.span());

    multisig.change_threshold(2);
    assert(multisig.get_threshold() == 2, 'new threshold not set');
}

#[test]
#[available_gas(20000000)]
fn add_signers() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 })];
    multisig.add_signers(2, new_signers);

    // check 
    let signers = multisig.get_signers_guid();
    assert(signers.len() == 2, 'invalid signers length');
    assert(multisig.get_threshold() == 2, 'new threshold not set');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/already-a-signer', 'ENTRYPOINT_FAILED'))]
fn add_signer_already_in_list() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // add signer
    let new_signers = array![Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 })];
    multisig.add_signers(2, new_signers);
}

#[test]
#[available_gas(20000000)]
fn get_name() {
    assert(initialize_multisig().get_name() == 'ArgentMultisig', 'Name should be ArgentMultisig');
}

#[test]
#[available_gas(20000000)]
fn get_version() {
    let version = initialize_multisig().get_version();
    assert(version.major == 0, 'Version major');
    assert(version.minor == 2, 'Version minor');
    assert(version.patch == 0, 'Version patch');
}
