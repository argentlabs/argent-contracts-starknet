use array::ArrayTrait;
use traits::Into;

use multisig::ArgentMultisigAccount;
use multisig::tests::initialize_multisig;
use multisig::tests::signer_pubkey_1;
use multisig::tests::signer_pubkey_2;
use multisig::tests::signer_pubkey_3;

#[test]
#[available_gas(20000000)]
fn remove_signers_first() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_1);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 2, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_signers_center() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_2);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 2, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}


#[test]
#[available_gas(20000000)]
fn remove_signers_last() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_3);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 2, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_1_and_2() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_1);
    signer_to_remove.append(signer_pubkey_2);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_1_and_3() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_1);
    signer_to_remove.append(signer_pubkey_3);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_2_and_3() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_2);
    signer_to_remove.append(signer_pubkey_3);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_2_and_1() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_2);
    signer_to_remove.append(signer_pubkey_1);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}


#[test]
#[available_gas(20000000)]
fn remove_3_and_1() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_3);
    signer_to_remove.append(signer_pubkey_1);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_3_and_2() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_3);
    signer_to_remove.append(signer_pubkey_2);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/not-a-signer', ))]
fn remove_invalid_signers() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(10);
    ArgentMultisigAccount::remove_signers(1, signer_to_remove);
}


#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/bad-threshold', ))]
fn remove_signers_invalid_threshold() {
    // init
    initialize_multisig();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_1);
    signer_to_remove.append(signer_pubkey_2);
    ArgentMultisigAccount::remove_signers(2, signer_to_remove);
}
