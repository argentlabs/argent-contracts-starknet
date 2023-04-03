use array::ArrayTrait;
use traits::Into;

use multisig::ArgentMultisigAccount;
use multisig::tests::initialize_multisig;
use multisig::tests::signer_pubkey_1;
use multisig::tests::signer_pubkey_2;
use multisig::tests::signer_pubkey_3;

#[test]
#[available_gas(20000000)]
fn replace_signer_1() {
    // init
    let threshold = 1_usize;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    ArgentMultisigAccount::constructor(threshold, signers_array);

    // replace signer
    let signer_to_add = signer_pubkey_2;
    ArgentMultisigAccount::replace_signer(signer_pubkey_1, signer_to_add);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1_usize, 'signer list changed size');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'threshold changed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_to_add), 'new was not added');
}


#[test]
#[available_gas(20000000)]
fn replace_signer_start() {
    // init
    initialize_multisig();

    // replace signer
    let signer_to_add = 5;
    ArgentMultisigAccount::replace_signer(signer_pubkey_1, signer_to_add);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 3_usize, 'signer list changed size');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'threshold changed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_to_add), 'new was not added');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn replace_signer_middle() {
    // init
    initialize_multisig();

    // replace signer
    let signer_to_add = 5;
    ArgentMultisigAccount::replace_signer(signer_pubkey_2, signer_to_add);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 3_usize, 'signer list changed size');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'threshold changed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_to_add), 'new was not added');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn replace_signer_end() {
    // init
    initialize_multisig();

    // replace signer
    let signer_to_add = 5;
    ArgentMultisigAccount::replace_signer(signer_pubkey_3, signer_to_add);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 3_usize, 'signer list changed size');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'threshold changed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_to_add), 'new was not added');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
}


#[test]
#[available_gas(20000000)]
#[should_panic(expected = ('argent/not-a-signer', ))]
fn replace_invalid_signer() {
    // init
    initialize_multisig();

    // replace signer
    let signer_to_add = 5;
    let not_a_signer = 10;
    ArgentMultisigAccount::replace_signer(not_a_signer, signer_to_add);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected = ('argent/already-a-signer', ))]
fn replace_already_signer() {
    // init
    initialize_multisig();

    // replace signer
    ArgentMultisigAccount::replace_signer(signer_pubkey_3, signer_pubkey_1);
}
