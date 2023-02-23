use array::ArrayTrait;
use contracts::ArgentMultisigAccount;
use debug::print_felt;
use traits::Into;

#[test]
#[available_gas(20000000)]
fn valid_initiliaze() {
    let threshold = 2_u32;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(1);
    signers_array.append(2);
    ArgentMultisigAccount::initialize(threshold, signers_array);
    assert(ArgentMultisigAccount::threshold::read() == threshold, 'new threshold not set');
}

#[test]
#[available_gas(20000000)]
fn change_threshold() {
    let threshold = 1_u32;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(1);
    signers_array.append(2);
    ArgentMultisigAccount::initialize(threshold, signers_array);
    assert(ArgentMultisigAccount::get_threshold() == threshold, 'new threshold not set');

    ArgentMultisigAccount::change_threshold(2_u32);
    assert(ArgentMultisigAccount::get_threshold() == 2_u32, 'new threshold not set');
}

