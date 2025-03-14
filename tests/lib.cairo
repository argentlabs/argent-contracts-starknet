#[cfg(test)]
mod test_argent_account;
#[cfg(test)]
mod test_argent_account_escape;
#[cfg(test)]
mod test_argent_account_signatures;
#[cfg(test)]
mod test_asserts;
// #[cfg(test)]
// mod test_comp_multisig;
// #[cfg(test)]
// mod test_comp_recovery_external;
// #[cfg(test)]
// mod test_comp_recovery_threshold;
#[cfg(test)]
mod test_comp_signer_list;
#[cfg(test)]
mod test_comp_src5;
#[cfg(test)]
mod test_eip191;
#[cfg(test)]
mod test_multicall;
// #[cfg(test)]
// mod test_multisig_account;
// #[cfg(test)]
// mod test_multisig_add_signers;
// #[cfg(test)]
// mod test_multisig_remove_signers;
// #[cfg(test)]
// mod test_multisig_replace_signer;
// #[cfg(test)]
// mod test_multisig_signing;
#[cfg(test)]
mod test_offchain_hashing;
#[cfg(test)]
mod test_secp256k1;
#[cfg(test)]
mod test_secp256r1;
#[cfg(test)]
mod test_transaction_version;

#[cfg(test)]
mod setup {
    #[cfg(test)]
    mod account_test_setup;
    #[cfg(test)]
    mod constants;
    // #[cfg(test)]
    // mod multisig_test_setup;
    #[cfg(test)]
    mod utils;
}

#[cfg(test)]
mod webauthn {
    #[cfg(test)]
    mod test_webauthn_bytes;
    #[cfg(test)]
    mod test_webauthn_sha256;
    #[cfg(test)]
    mod test_webauthn_validation;
}
