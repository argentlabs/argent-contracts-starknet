use array::ArrayTrait;
use traits::Into;

use contracts::ArgentMultisigAccount;

const signer_pubkey_1: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const signer_pubkey_2: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_pubkey_3: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;


fn _initialize() {
    let threshold = 1_u32;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    signers_array.append(signer_pubkey_2);
    signers_array.append(signer_pubkey_3);
    ArgentMultisigAccount::initialize(threshold, signers_array);
}

#[test]
#[available_gas(20000000)]
fn replace_signer_1() {
    // init
    let threshold = 1_u32;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    ArgentMultisigAccount::initialize(threshold, signers_array);

    // replace signer
    let signer_to_add = signer_pubkey_2;
    ArgentMultisigAccount::replace_signer(signer_pubkey_1, signer_to_add);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 1_usize, 'signer list changed size');
    assert(ArgentMultisigAccount::get_threshold() == 1_u32, 'threshold changed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_to_add), 'new was not added');
}


#[test]
#[available_gas(20000000)]
fn replace_signer_start() {
    // init
    _initialize();

    // replace signer
    let signer_to_add = 5;
    ArgentMultisigAccount::replace_signer(signer_pubkey_1, signer_to_add);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 3_usize, 'signer list changed size');
    assert(ArgentMultisigAccount::get_threshold() == 1_u32, 'threshold changed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_1)), 'signer 1 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_to_add), 'new was not added');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_2), 'signer 2 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn replace_signer_middle() {
    // init
    _initialize();

    // replace signer
    let signer_to_add = 5;
    ArgentMultisigAccount::replace_signer(signer_pubkey_2, signer_to_add);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 3_usize, 'signer list changed size');
    assert(ArgentMultisigAccount::get_threshold() == 1_u32, 'threshold changed');
    assert(!(ArgentMultisigAccount::is_signer(signer_pubkey_2)), 'signer 2 was not removed');
    assert(ArgentMultisigAccount::is_signer(signer_to_add), 'new was not added');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_1), 'signer 1 was removed');
    assert(ArgentMultisigAccount::is_signer(signer_pubkey_3), 'signer 3 was removed');
}

#[test]
#[available_gas(20000000)]
fn replace_signer_end() {
    // init
    _initialize();

    // replace signer
    let signer_to_add = 5;
    ArgentMultisigAccount::replace_signer(signer_pubkey_3, signer_to_add);

    // check 
    let signers = ArgentMultisigAccount::get_signers();
    assert(signers.len() == 3_usize, 'signer list changed size');
    assert(ArgentMultisigAccount::get_threshold() == 1_u32, 'threshold changed');
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
    _initialize();

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
    _initialize();

    // replace signer
    ArgentMultisigAccount::replace_signer(signer_pubkey_3, signer_pubkey_1);
}
