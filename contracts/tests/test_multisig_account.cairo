use array::ArrayTrait;
use contracts::ArgentMultisigAccount;
use debug::print_felt;
use traits::Into;

#[test]
#[available_gas(20000000)]
fn valid_initiliaze() {
    let threshold = 2;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(1);
    signers_array.append(2);
    ArgentMultisigAccount::initialize(threshold, signers_array);
    assert(ArgentMultisigAccount::threshold::read() == threshold, 'new threshold not set');
}

