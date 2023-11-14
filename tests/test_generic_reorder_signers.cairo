use argent::tests::setup::generic_test_setup::{
    initialize_generic_with, signer_pubkey_1, signer_pubkey_2, signer_pubkey_3,
    ITestArgentGenericAccountDispatcherTrait, initialize_generic_with_one_signer
};
use debug::PrintTrait;

#[test]
#[available_gas(20000000)]
fn reorder_2_signers() {
    // init
    let threshold = 2;
    let init_order = array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3];
    let multisig = initialize_generic_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_pubkey_1, 'signer 1 wrong init');
    assert(*signers.at(1) == signer_pubkey_2, 'signer 2 wrong init');
    assert(*signers.at(2) == signer_pubkey_3, 'signer 3 wrong init');

    // reoder signers
    let new_order = array![signer_pubkey_1, signer_pubkey_3, signer_pubkey_2];
    multisig.reorder_signers(new_order);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 3, 'invalid signers length');
    assert(*signers.at(0) == signer_pubkey_1, 'signer 1 was moved');
    assert(*signers.at(1) == signer_pubkey_3, 'signer 2 was not moved');
    assert(*signers.at(2) == signer_pubkey_2, 'signer 3 was not moved');
}

#[test]
#[available_gas(20000000)]
fn reorder_3_signers() {
    // init
    let threshold = 2;
    let init_order = array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3];
    let multisig = initialize_generic_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_pubkey_1, 'signer 1 wrong init');
    assert(*signers.at(1) == signer_pubkey_2, 'signer 2 wrong init');
    assert(*signers.at(2) == signer_pubkey_3, 'signer 3 wrong init');

    // reoder signers
    let new_order = array![signer_pubkey_3, signer_pubkey_2, signer_pubkey_1];
    multisig.reorder_signers(new_order);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 3, 'invalid signers length');
    assert(*signers.at(0) == signer_pubkey_3, 'signer 1 was not moved');
    assert(*signers.at(1) == signer_pubkey_2, 'signer 2 was not moved');
    assert(*signers.at(2) == signer_pubkey_1, 'signer 3 was not moved');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/too-short', 'ENTRYPOINT_FAILED'))]
fn reorder_signers_wrong_length() {
    // init
    let threshold = 2;
    let init_order = array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3];
    let multisig = initialize_generic_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_pubkey_1, 'signer 1 wrong init');
    assert(*signers.at(1) == signer_pubkey_2, 'signer 2 wrong init');
    assert(*signers.at(2) == signer_pubkey_3, 'signer 3 wrong init');

    // reoder signers
    let new_order = array![signer_pubkey_3, signer_pubkey_2];
    multisig.reorder_signers(new_order);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/unknown-signer', 'ENTRYPOINT_FAILED'))]
fn reorder_signers_wrong_signer() {
    // init
    let threshold = 2;
    let init_order = array![signer_pubkey_1, signer_pubkey_2];
    let multisig = initialize_generic_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 2, 'invalid init signers length');
    assert(*signers.at(0) == signer_pubkey_1, 'signer 1 wrong init');
    assert(*signers.at(1) == signer_pubkey_2, 'signer 2 wrong init');

    // reoder signers
    let new_order = array![signer_pubkey_3, signer_pubkey_2];
    multisig.reorder_signers(new_order);
}

