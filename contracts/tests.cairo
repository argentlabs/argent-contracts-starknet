mod test_asserts;
mod test_argent_account;
mod test_argent_account_signatures;
mod test_multisig_account;
mod test_multisig_remove_signers;
mod test_multisig_replace_signers;
mod test_multisig_signing;
mod test_argent_account_escape;

use contracts::ArgentAccount;

const signer_pubkey: felt = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const guardian_pubkey: felt = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const guardian_backup_pubkey: felt =
    0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;
const wrong_signer_pubkey: felt = 0x743829e0a179f8afe223fc8112dfc8d024ab6b235fd42283c4f5970259ce7b7;
const wrong_guardian_pubkey: felt =
    0x6eeee2b0c71d681692559735e08a2c3ba04e7347c0c18d4d49b83bb89771591;

fn initialize_account() {
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, 0);
}

fn initialize_account_without_guardian() {
    ArgentAccount::initialize(signer_pubkey, 0, 0);
}

fn initialize_account_with_guardian_backup() {
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, guardian_backup_pubkey);
}

