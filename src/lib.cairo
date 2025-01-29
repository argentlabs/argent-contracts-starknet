// TODO LIST:
// Which should be pub(crate)?
mod recovery;
// mod upgrade {
//     mod interface;
//     mod upgrade;
// }

// mod account {
//     mod interface;
// }

// mod introspection {
//     mod interface;
//     mod src5;
// }

mod signer {
    mod eip191;
    mod signer_signature;
    mod webauthn;
}

// mod outside_execution {
//     mod interface;
//     mod outside_execution;
//     mod outside_execution_hash;
// }

// mod multisig_account {
//     mod multisig_account;
//     mod upgrade_migration;
//     mod external_recovery {
//         mod external_recovery;
//         mod interface;
//         mod packing;
//     }
//     mod signer_manager {
//         mod interface;
//         mod signer_manager;
//     }
// }

// mod multiowner_account {
//     mod account_interface;
//     mod argent_account;
//     mod events;
//     mod guardian_manager;
//     mod owner_manager;
//     mod recovery;
//     mod replace_owners_message;
//     mod signer_storage_linked_set;
//     mod upgrade_migration;
// }

mod utils {
    pub mod array_ext;
    mod asserts;
    pub mod bytes;
    mod calls;
    pub mod hashing;
    //     mod linked_set;
    //     mod linked_set_with_head;
    mod serialization;
    mod transaction_version;
}

// mod mocks {
//     mod future_argent_account;
//     mod future_argent_multisig;
//     mod linked_set_mock;
//     mod mock_dapp;
//     mod multiowner_mock;
//     mod multisig_mocks;
//     mod recovery_mocks;
//     mod signature_verifier;
//     mod src5_mocks;
// }

// mod session {
//     mod interface;
//     mod session;
//     mod session_hash;
// }

mod offchain_message {
    mod interface;
    mod precalculated_hashing;
}

