mod account {
    mod argent_account;
    mod escape;
    mod interface;
}
mod common {
    mod account;
    mod array_ext;
    mod asserts;
    mod calls;
    mod erc165;
    mod multicall;
    mod outside_execution;
    mod test_dapp;
    mod upgrade;
    mod version;
}
mod multisig {
    mod argent_multisig;
    mod interface;
    mod signer_signature;
}
mod generic {
    mod argent_generic;
    mod interface;
    mod recovery;
    mod signer_signature;
}
#[cfg(test)]
mod tests {
    mod test_argent_account;
    mod test_argent_account_signatures;
    mod test_asserts;
    mod test_generic_reorder_signers;
    mod test_generic_signing;
    mod test_multicall;
    mod test_multisig_account;
    mod test_multisig_remove_signers;
    mod test_multisig_replace_signers;
    mod test_multisig_signing;
    mod setup {
        mod account_test_setup;
        mod generic_test_setup;
        mod multisig_test_setup;
    }
}
