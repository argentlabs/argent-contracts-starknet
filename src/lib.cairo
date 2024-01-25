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
    mod transaction_version;
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
mod mocks {
    mod erc20;
    mod test_dapp;
}
mod session {
    mod session;
    mod session_account;
    mod session_structs;
}
