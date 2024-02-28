mod upgrade {
    mod interface;
    mod upgrade;
}

mod account {
    mod interface;
}

mod introspection {
    mod interface;
    mod src5;
}

mod multisig {
    mod interface;
    mod multisig;
}

mod signer {
    mod signer_signature;
    mod webauthn;
}

mod signer_storage {
    mod interface;
    mod signer_list;
}

mod outside_execution {
    mod interface;
    mod outside_execution;
}

mod recovery {
    mod external_recovery;
    mod interface;
    mod threshold_recovery;
}

mod presets {
    mod argent_account;
    mod multisig_account;
    mod user_account;
}

mod utils {
    mod array_ext;
    mod asserts;
    mod bytes;
    mod calls;
    mod multicall;
    mod serialization;
    mod test_dapp;
    mod transaction_version;
}

mod mocks {
    mod multisig_mocks;
    mod recovery_mocks;
    mod signer_list_mocks;
    mod src5_mocks;
}
