mod test_argent_account;
mod test_argent_account_escape;
mod test_argent_account_signatures;

use array::ArrayTrait;
use account::ArgentAccount;


const owner_pubkey: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const guardian_pubkey: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const wrong_owner_pubkey: felt252 =
    0x743829e0a179f8afe223fc8112dfc8d024ab6b235fd42283c4f5970259ce7b7;
const wrong_guardian_pubkey: felt252 =
    0x6eeee2b0c71d681692559735e08a2c3ba04e7347c0c18d4d49b83bb89771591;

fn initialize_account() {
    ArgentAccount::constructor(owner_pubkey, guardian_pubkey);
}

fn initialize_account_without_guardian() {
    ArgentAccount::constructor(owner_pubkey, 0);
}
