mod test_multisig_account;
mod test_multisig_remove_signers;
mod test_multisig_replace_signers;
mod test_multisig_signing;

use array::ArrayTrait;
use multisig::ArgentMultisig;

const signer_pubkey_1: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const signer_pubkey_2: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_pubkey_3: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;

fn initialize_multisig() {
    let threshold = 1;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    signers_array.append(signer_pubkey_2);
    signers_array.append(signer_pubkey_3);
    ArgentMultisig::constructor(threshold, signers_array);
}
