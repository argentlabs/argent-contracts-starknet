mod account {
    mod argent_account;
    mod escape;
    mod interface;
}

mod common {
    mod account;
    mod array_ext;
    mod asserts;
    mod bytes;
    mod calls;
    mod erc165;
    mod interface;
    mod multicall;
    mod outside_execution;
    mod serialization;
    mod signer_list;
    mod signer_signature;
    mod test_dapp;
    mod transaction_version;
    mod upgrade;
    mod version;
    mod webauthn;
}

mod multisig {
    mod argent_multisig;
    mod interface;
}

mod generic {
    mod argent_generic;
    mod interface;
    mod recovery;
}
