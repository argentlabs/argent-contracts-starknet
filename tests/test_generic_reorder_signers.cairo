use argent::common::signer_signature::IntoGuid;
use argent::common::signer_signature::{Signer, StarknetSigner, SignerSignature};
use argent_tests::setup::generic_test_setup::{
    initialize_generic_with, signer_pubkey_1, signer_pubkey_2, signer_pubkey_3,
    ITestArgentGenericAccountDispatcherTrait, initialize_generic_with_one_signer
};

#[test]
#[available_gas(20000000)]
fn reorder_2_signers() {
    // init
    let threshold = 2;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let signer_3 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_3 });
    let init_order = array![signer_1, signer_2, signer_3];
    let multisig = initialize_generic_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_1.into_guid().unwrap(), 'signer 1 wrong init');
    assert(*signers.at(1) == signer_2.into_guid().unwrap(), 'signer 2 wrong init');
    assert(*signers.at(2) == signer_3.into_guid().unwrap(), 'signer 3 wrong init');

    // reoder signers
    let new_order = array![signer_1, signer_3, signer_2];
    multisig.reorder_signers(new_order);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid signers length');
    assert(*signers.at(0) == signer_1.into_guid().unwrap(), 'signer 1 was moved');
    assert(*signers.at(1) == signer_3.into_guid().unwrap(), 'signer 2 was not moved');
    assert(*signers.at(2) == signer_2.into_guid().unwrap(), 'signer 3 was not moved');
}

#[test]
#[available_gas(20000000)]
fn reorder_3_signers() {
    // init
    let threshold = 2;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let signer_3 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_3 });
    let init_order = array![signer_1, signer_2, signer_3];
    let multisig = initialize_generic_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_1.into_guid().unwrap(), 'signer 1 wrong init');
    assert(*signers.at(1) == signer_2.into_guid().unwrap(), 'signer 2 wrong init');
    assert(*signers.at(2) == signer_3.into_guid().unwrap(), 'signer 3 wrong init');

    // reoder signers
    let new_order = array![signer_3, signer_2, signer_1];
    multisig.reorder_signers(new_order);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid signers length');
    assert(*signers.at(0) == signer_3.into_guid().unwrap(), 'signer 1 was not moved');
    assert(*signers.at(1) == signer_2.into_guid().unwrap(), 'signer 2 was not moved');
    assert(*signers.at(2) == signer_1.into_guid().unwrap(), 'signer 3 was not moved');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/too-short', 'ENTRYPOINT_FAILED'))]
fn reorder_signers_wrong_length() {
    // init
    let threshold = 2;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let signer_3 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_3 });
    let init_order = array![signer_1, signer_2, signer_3];
    let multisig = initialize_generic_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 3, 'invalid init signers length');
    assert(*signers.at(0) == signer_1.into_guid().unwrap(), 'signer 1 wrong init');
    assert(*signers.at(1) == signer_2.into_guid().unwrap(), 'signer 2 wrong init');
    assert(*signers.at(2) == signer_3.into_guid().unwrap(), 'signer 3 wrong init');

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
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let signer_3 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_3 });
    let init_order = array![signer_1, signer_2];
    let multisig = initialize_generic_with(threshold, init_order.span());

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 2, 'invalid init signers length');
    assert(*signers.at(0) == signer_1.into_guid().unwrap(), 'signer 1 wrong init');
    assert(*signers.at(1) == signer_2.into_guid().unwrap(), 'signer 2 wrong init');

    // reoder signers
    let new_order = array![signer_3, signer_2];
    multisig.reorder_signers(new_order);
}

