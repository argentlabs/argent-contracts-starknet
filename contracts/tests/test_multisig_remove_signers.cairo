use array::ArrayTrait;
use contracts::ArgentMultisigAccount;
use traits::Into;

const signer_pubkey_1: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const signer_pubkey_2: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_pubkey_3: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;


fn _initialize() {
    let threshold = 1_usize;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    signers_array.append(signer_pubkey_2);
    signers_array.append(signer_pubkey_3);
    ArgentMultisigAccount::initialize(threshold, signers_array);
}

#[test]
#[available_gas(20000000)]
fn remove_signers_first() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_1);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 2_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_signers_center() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_2);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 2_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}


#[test]
#[available_gas(20000000)]
fn remove_signers_last() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_3);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 2_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_1_and_2() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_1);
    signer_to_remove.append(signer_pubkey_2);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_1_and_3() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_1);
    signer_to_remove.append(signer_pubkey_3);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_2_and_3() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_2);
    signer_to_remove.append(signer_pubkey_3);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_2_and_1() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_2);
    signer_to_remove.append(signer_pubkey_1);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}


#[test]
#[available_gas(20000000)]
fn remove_3_and_1() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_3);
    signer_to_remove.append(signer_pubkey_1);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
}

#[test]
#[available_gas(20000000)]
fn remove_3_and_2() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_3);
    signer_to_remove.append(signer_pubkey_2);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1_usize, 'invalid signers length');
    assert(ArgentMultisigAccount::get_threshold() == 1_usize, 'new threshold not set');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_3)), 'signer 3 was not removed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected = ('argent/not-a-signer', ))]
fn remove_invalid_signers() {
    // init
    let threshold = 1_usize;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    signers_array.append(signer_pubkey_2);
    ArgentMultisigAccount::initialize(threshold, signers_array);

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(10);
    ArgentMultisigAccount::remove_signers(1_usize, signer_to_remove);
}


#[test]
#[available_gas(20000000)]
#[should_panic(expected = ('argent/bad-threshold', ))]
fn remove_signers_invalid_threshold() {
    // init
    _initialize();

    // remove signer
    let mut signer_to_remove = ArrayTrait::new();
    signer_to_remove.append(signer_pubkey_1);
    signer_to_remove.append(signer_pubkey_2);
    ArgentMultisigAccount::remove_signers(2_usize, signer_to_remove);
}
