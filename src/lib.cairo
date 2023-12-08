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

    mod upgrade;
    mod version;
}
mod mocks {
    mod test_dapp;
    mod erc20;
}
mod session {
    mod session;
    mod session_account;
    mod session_structs;
}
mod multisig {
    mod argent_multisig;
    mod interface;
    mod signer_signature;
}
