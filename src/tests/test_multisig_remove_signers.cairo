use argent::tests::setup::multisig_test_setup::{
    initialize_multisig, signer_pubkey_1, signer_pubkey_2, signer_pubkey_3,
    ITestArgentMultisigDispatcherTrait
};

#[test]
#[available_gas(20000000)]
fn remove_signers_first() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_1];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 2, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_1), 'signer 1 was not removed');
    assert(multisig.is_signer(signer_pubkey_2), 'signer 2 was removed');
    assert(multisig.is_signer(signer_pubkey_3), 'signer 3 was removed');
}
#[test]
#[available_gas(20000000)]
fn remove_signers_center() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_2];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 2, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_2), 'signer 2 was not removed');
    assert(multisig.is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(multisig.is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_signers_last() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 2, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_3), 'signer 3 was not removed');
    assert(multisig.is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(multisig.is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_1_and_2() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_1, signer_pubkey_2];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_1), 'signer 1 was not removed');
    assert(!multisig.is_signer(signer_pubkey_2), 'signer 2 was not removed');
    assert(multisig.is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_1_and_3() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_1, signer_pubkey_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_1), 'signer 1 was not removed');
    assert(!multisig.is_signer(signer_pubkey_3), 'signer 3 was not removed');
    assert(multisig.is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_2_and_3() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_2, signer_pubkey_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_2), 'signer 2 was not removed');
    assert(!multisig.is_signer(signer_pubkey_3), 'signer 3 was not removed');
    assert(multisig.is_signer(signer_pubkey_1), 'signer 1 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_2_and_1() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_2, signer_pubkey_1];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_2), 'signer 2 was not removed');
    assert(!multisig.is_signer(signer_pubkey_1), 'signer 1 was not removed');
    assert(multisig.is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_3_and_1() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_3, signer_pubkey_1];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_3), 'signer 3 was not removed');
    assert(!multisig.is_signer(signer_pubkey_1), 'signer 1 was not removed');
    assert(multisig.is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_3_and_2() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_2, signer_pubkey_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_pubkey_3), 'signer 3 was not removed');
    assert(!multisig.is_signer(signer_pubkey_2), 'signer 2 was not removed');
    assert(multisig.is_signer(signer_pubkey_1), 'signer 1 was removed');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/not-a-signer', 'ENTRYPOINT_FAILED'))]
fn remove_invalid_signers() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![10];
    multisig.remove_signers(1, signer_to_remove);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/bad-threshold', 'ENTRYPOINT_FAILED'))]
fn remove_signers_invalid_threshold() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![signer_pubkey_1, signer_pubkey_2];
    multisig.remove_signers(2, signer_to_remove);
}
