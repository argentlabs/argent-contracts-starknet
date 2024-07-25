// mod upgrade {
//     mod interface;
//     mod upgrade;
// }

mod account {
    mod interface;
}

// mod introspection {
//     mod interface;
//     mod src5;
// }

// mod multisig {
//     mod interface;
//     mod multisig;
// }

mod signer {
    mod eip191;
    mod signer_signature;
    mod webauthn;
}

mod signer_storage {
    mod interface;
    mod signer_list;
}

// mod outside_execution {
//     mod interface;
//     mod outside_execution;
//     mod outside_execution_hash;
// }

mod recovery {
    mod interface;
    mod threshold_recovery;
}

// mod external_recovery {
//     mod external_recovery;
//     mod interface;
// }

// mod presets {
//     mod argent_account;
//     mod multisig_account;
//     mod user_account;
// }

mod utils {
    mod array_ext;
    mod array_store;
    mod asserts;
    mod bytes;
    mod calls;
    mod hashing;
    mod multicall;
    mod serialization;
    mod transaction_version;
}
// mod mocks {
//     mod future_argent_account;
//     mod future_argent_multisig;
//     mod mock_dapp;
//     mod mock_erc20;
//     mod multisig_mocks;
//     mod recovery_mocks;
//     mod signature_verifier;
//     mod signer_list_mocks;
//     mod src5_mocks;
// }

// mod session {
//     mod interface;
//     mod session;
//     mod session_hash;
// }

// mod offchain_message {
//     mod interface;
//     mod precalculated_hashing;
// }


