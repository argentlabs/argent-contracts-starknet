mod account {
    mod argent_account;
    mod interface;
    mod escape;
}
mod common {
    mod account;
    mod array_ext;
    mod asserts;
    mod calls;
    mod erc165;
    mod outside_execution;
    mod test_dapp;
    mod upgrade;
    mod version;
    mod multicall;
}
mod multisig {
    mod argent_multisig;
    mod interface;
    mod signer_signature;
}
#[cfg(test)]
mod testing {
    mod account_test_setup;
    mod multisig_test_setup;
}
