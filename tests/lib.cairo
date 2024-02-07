mod test_argent_account;
mod test_argent_account_signatures;
mod test_asserts;
mod test_multicall;
mod test_multisig_account;
mod test_multisig_remove_signers;
mod test_multisig_replace_signers;
mod test_multisig_reorder_signers;
mod test_multisig_signing;
mod test_transaction_version;
mod setup {
    mod account_test_setup;
    mod multisig_test_setup;
    mod utils;
    mod webauthn_test_setup;
}

mod webauthn {
    mod test_webauthn_base64;
    mod test_webauthn_bytes;
    mod test_webauthn_sha256;
}
