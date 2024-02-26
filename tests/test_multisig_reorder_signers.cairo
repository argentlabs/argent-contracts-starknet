use argent::signer::signer_signature::SignerTrait;
use argent::signer::signer_signature::{Signer, StarknetSigner, SignerSignature, starknetSignerFromPubKey};
use argent_tests::setup::multisig_test_setup::{
    initialize_multisig, initialize_multisig_with, signer_pubkey_1, signer_pubkey_2, signer_pubkey_3,
    ITestArgentMultisigDispatcherTrait
};

#[test]
#[available_gas(20000000)]
fn reorder_2_signers() {
    // init
    let threshold = 2;
    let signer_1 = starknetSignerFromPubKey(signer_pubkey_1);
    let signer_2 = starknetSignerFromPubKey(signer_pubkey_2);
    let signer_3 = starknetSignerFromPubKey(signer_pubkey_3);
    let init_order = array![signer_1, signer_2, signer_3];
    let multisig = initialize_multisig_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_1.into_guid(), 'signer 1 wrong init');
    assert(*signers.at(1) == signer_2.into_guid(), 'signer 2 wrong init');
    assert(*signers.at(2) == signer_3.into_guid(), 'signer 3 wrong init');

    // reoder signers
    let new_order = array![signer_1, signer_3, signer_2];
    multisig.reorder_signers(new_order);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid signers length');
    assert(*signers.at(0) == signer_1.into_guid(), 'signer 1 was moved');
    assert(*signers.at(1) == signer_3.into_guid(), 'signer 2 was not moved');
    assert(*signers.at(2) == signer_2.into_guid(), 'signer 3 was not moved');
}

#[test]
#[available_gas(20000000)]
fn reorder_3_signers() {
    // init
    let threshold = 2;
    let signer_1 = starknetSignerFromPubKey(signer_pubkey_1);
    let signer_2 = starknetSignerFromPubKey(signer_pubkey_2);
    let signer_3 = starknetSignerFromPubKey(signer_pubkey_3);
    let init_order = array![signer_1, signer_2, signer_3];
    let multisig = initialize_multisig_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_1.into_guid(), 'signer 1 wrong init');
    assert(*signers.at(1) == signer_2.into_guid(), 'signer 2 wrong init');
    assert(*signers.at(2) == signer_3.into_guid(), 'signer 3 wrong init');

    // reoder signers
    let new_order = array![signer_3, signer_2, signer_1];
    multisig.reorder_signers(new_order);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid signers length');
    assert(*signers.at(0) == signer_3.into_guid(), 'signer 1 was not moved');
    assert(*signers.at(1) == signer_2.into_guid(), 'signer 2 was not moved');
    assert(*signers.at(2) == signer_1.into_guid(), 'signer 3 was not moved');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/too-short', 'ENTRYPOINT_FAILED'))]
fn reorder_signers_wrong_length() {
    // init
    let threshold = 2;
    let signer_1 = starknetSignerFromPubKey(signer_pubkey_1);
    let signer_2 = starknetSignerFromPubKey(signer_pubkey_2);
    let signer_3 = starknetSignerFromPubKey(signer_pubkey_3);
    let init_order = array![signer_1, signer_2, signer_3];
    let multisig = initialize_multisig_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_1.into_guid(), 'signer 1 wrong init');
    assert(*signers.at(1) == signer_2.into_guid(), 'signer 2 wrong init');
    assert(*signers.at(2) == signer_3.into_guid(), 'signer 3 wrong init');

    // reoder signers
    let new_order = array![signer_3, signer_2];
    multisig.reorder_signers(new_order);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/not-a-signer', 'ENTRYPOINT_FAILED'))]
fn reorder_signers_wrong_signer() {
    // init
    let threshold = 2;
    let signer_1 = starknetSignerFromPubKey(signer_pubkey_1);
    let signer_2 = starknetSignerFromPubKey(signer_pubkey_2);
    let signer_3 = starknetSignerFromPubKey(signer_pubkey_3);
    let init_order = array![signer_1, signer_2];
    let multisig = initialize_multisig_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 2, 'invalid init signers length');
    assert(*signers.at(0) == signer_1.into_guid(), 'signer 1 wrong init');
    assert(*signers.at(1) == signer_2.into_guid(), 'signer 2 wrong init');

    // reoder signers
    let new_order = array![signer_3, signer_2];
    multisig.reorder_signers(new_order);
}

