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
    mod signer_list;
    mod signer_signature;
}

mod generic {
    mod argent_generic;
    mod interface;
    mod recovery;
    mod signer_signature;
}
