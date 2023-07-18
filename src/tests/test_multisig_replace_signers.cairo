use array::ArrayTrait;
use traits::Into;

use argent::tests::setup::multisig_test_setup::{
    initialize_multisig, signer_pubkey_1, signer_pubkey_2, signer_pubkey_3,
    ITestArgentMultisigDispatcherTrait, initialize_multisig_with_one_signer
};

#[test]
#[available_gas(20000000)]
fn replace_signer_1() {
    // init
    let multisig = initialize_multisig_with_one_signer();

    // replace signer
    let signer_to_add = signer_pubkey_2;
    multisig.replace_signer(signer_pubkey_1, signer_to_add);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 1, 'signer list changed size');
    assert(multisig.get_threshold() == 1, 'threshold changed');
    assert(!multisig.is_signer(signer_pubkey_1), 'signer 1 was not removed');
    assert(multisig.is_signer(signer_to_add), 'new was not added');
}

#[test]
#[available_gas(20000000)]
fn replace_signer_start() {
    // init
    let multisig = initialize_multisig();

    // replace signer
    let signer_to_add = 5;
    multisig.replace_signer(signer_pubkey_1, signer_to_add);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 3, 'signer list changed size');
    assert(multisig.get_threshold() == 1, 'threshold changed');
    assert(!multisig.is_signer(signer_pubkey_1), 'signer 1 was not removed');
    assert(multisig.is_signer(signer_to_add), 'new was not added');
    assert(multisig.is_signer(signer_pubkey_2), 'signer 2 was removed');
    assert(multisig.is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn replace_signer_middle() {
    // init
    let multisig = initialize_multisig();

    // replace signer
    let signer_to_add = 5;
    multisig.replace_signer(signer_pubkey_2, signer_to_add);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 3, 'signer list changed size');
    assert(multisig.get_threshold() == 1, 'threshold changed');
    assert(!multisig.is_signer(signer_pubkey_2), 'signer 2 was not removed');
    assert(multisig.is_signer(signer_to_add), 'new was not added');
    assert(multisig.is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(multisig.is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn replace_signer_end() {
    // init
    let multisig = initialize_multisig();

    // replace signer
    let signer_to_add = 5;
    multisig.replace_signer(signer_pubkey_3, signer_to_add);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 3, 'signer list changed size');
    assert(multisig.get_threshold() == 1, 'threshold changed');
    assert(!multisig.is_signer(signer_pubkey_3), 'signer 3 was not removed');
    assert(multisig.is_signer(signer_to_add), 'new was not added');
    assert(multisig.is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(multisig.is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/not-a-signer', 'ENTRYPOINT_FAILED'))]
fn replace_invalid_signer() {
    // init
    let multisig = initialize_multisig();

    // replace signer
    let signer_to_add = 5;
    let not_a_signer = 10;
    multisig.replace_signer(not_a_signer, signer_to_add);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/already-a-signer', 'ENTRYPOINT_FAILED'))]
fn replace_already_signer() {
    // init
    let multisig = initialize_multisig();

    // replace signer
    multisig.replace_signer(signer_pubkey_3, signer_pubkey_1);
}
