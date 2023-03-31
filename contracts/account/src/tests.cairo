mod test_argent_account;
mod test_argent_account_escape;
mod test_argent_account_signatures;

use account::ArgentAccount;

const owner_pubkey: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const guardian_pubkey: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const guardian_backup_pubkey: felt252 =
    0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;
const wrong_owner_pubkey: felt252 =
    0x743829e0a179f8afe223fc8112dfc8d024ab6b235fd42283c4f5970259ce7b7;
const wrong_guardian_pubkey: felt252 =
    0x6eeee2b0c71d681692559735e08a2c3ba04e7347c0c18d4d49b83bb89771591;

fn initialize_account() {
    ArgentAccount::initialize(owner_pubkey, guardian_pubkey, 0);
}

fn initialize_account_without_guardian() {
    ArgentAccount::initialize(owner_pubkey, 0, 0);
}

fn initialize_account_with_guardian_backup() {
    ArgentAccount::initialize(owner_pubkey, guardian_pubkey, guardian_backup_pubkey);
}


const signer_pubkey_1: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const signer_pubkey_2: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_pubkey_3: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;

fn initialize_multisig() {
    let threshold = 1_usize;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_1);
    signers_array.append(signer_pubkey_2);
    signers_array.append(signer_pubkey_3);
    ArgentMultisigAccount::constructor(threshold, signers_array);
}
