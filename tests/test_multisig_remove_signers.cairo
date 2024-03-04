use argent::signer::signer_signature::{Signer, StarknetSigner, SignerSignature, starknet_signer_from_pubkey};
use super::setup::constants::{MULTISIG_OWNER};
use super::setup::multisig_test_setup::{
    initialize_multisig, initialize_multisig_with, ITestArgentMultisigDispatcherTrait
};


#[test]
fn remove_signers_first() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_1];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 2, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_1), 'signer 1 was not removed');
    assert(multisig.is_signer(signer_2), 'signer 2 was removed');
    assert(multisig.is_signer(signer_3), 'signer 3 was removed');
}
#[test]
fn remove_signers_center() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_2];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 2, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_2), 'signer 2 was not removed');
    assert(multisig.is_signer(signer_1), 'signer 1 was removed');
    assert(multisig.is_signer(signer_3), 'signer 3 was removed');
}

#[test]
fn remove_signers_last() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 2, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_3), 'signer 3 was not removed');
    assert(multisig.is_signer(signer_1), 'signer 1 was removed');
    assert(multisig.is_signer(signer_2), 'signer 2 was removed');
}

#[test]
fn remove_1_and_2() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_1, signer_2];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_1), 'signer 1 was not removed');
    assert(!multisig.is_signer(signer_2), 'signer 2 was not removed');
    assert(multisig.is_signer(signer_3), 'signer 3 was removed');
}

#[test]
fn remove_1_and_3() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_1, signer_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_1), 'signer 1 was not removed');
    assert(!multisig.is_signer(signer_3), 'signer 3 was not removed');
    assert(multisig.is_signer(signer_2), 'signer 2 was removed');
}

#[test]
fn remove_2_and_3() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_2, signer_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_2), 'signer 2 was not removed');
    assert(!multisig.is_signer(signer_3), 'signer 3 was not removed');
    assert(multisig.is_signer(signer_1), 'signer 1 was removed');
}

#[test]
fn remove_2_and_1() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_2, signer_1];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_2), 'signer 2 was not removed');
    assert(!multisig.is_signer(signer_1), 'signer 1 was not removed');
    assert(multisig.is_signer(signer_3), 'signer 3 was removed');
}

#[test]
fn remove_3_and_1() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_3, signer_1];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_3), 'signer 3 was not removed');
    assert(!multisig.is_signer(signer_1), 'signer 1 was not removed');
    assert(multisig.is_signer(signer_2), 'signer 2 was removed');
}

#[test]
fn remove_3_and_2() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_2, signer_3];
    multisig.remove_signers(1, signer_to_remove);

    // check 
    let signers = multisig.get_signer_guids();
    assert(signers.len() == 1, 'invalid signers length');
    assert(multisig.get_threshold() == 1, 'new threshold not set');
    assert(!multisig.is_signer(signer_3), 'signer 3 was not removed');
    assert(!multisig.is_signer(signer_2), 'signer 2 was not removed');
    assert(multisig.is_signer(signer_1), 'signer 1 was removed');
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn remove_invalid_signers() {
    // init
    let multisig = initialize_multisig();

    // remove signer
    let signer_to_remove = array![starknet_signer_from_pubkey(10)];
    multisig.remove_signers(1, signer_to_remove);
}

#[test]
#[should_panic(expected: ('argent/bad-threshold',))]
fn remove_signers_invalid_threshold() {
    // init
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1));
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2));
    let signer_3 = starknet_signer_from_pubkey(MULTISIG_OWNER(3));
    let multisig = initialize_multisig_with(threshold: 1, signers: array![signer_1, signer_2, signer_3].span());

    // remove signer
    let signer_to_remove = array![signer_1, signer_2];
    multisig.remove_signers(2, signer_to_remove);
}

