mod test_argent_account;
mod test_argent_account_escape;
mod test_argent_account_signatures;
mod test_asserts;
mod test_comp_multisig;
mod test_comp_recovery_external;
mod test_comp_recovery_threshold;
mod test_comp_signer_list;
mod test_comp_src5;
mod test_eip191;
mod test_multicall;
mod test_multisig_account;
mod test_multisig_add_signers;
// mod test_multisig_remove_signers;
// mod test_multisig_replace_signer;
mod test_multisig_signing;
mod test_offchain_hashing;
mod test_secp256k1;
mod test_secp256r1;
mod test_transaction_version;

mod setup {
    mod account_test_setup;
    mod constants;
    mod multisig_test_setup;
    mod utils;
}
// mod webauthn {
//     mod test_webauthn_bytes;
//     mod test_webauthn_sha256;
//     mod test_webauthn_validation;
// }


