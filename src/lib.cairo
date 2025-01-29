// TODO LIST:
// Which should be pub(crate)?
mod recovery;

mod upgrade {
    pub mod interface;
    pub mod upgrade;
}

mod account {
    pub mod interface;
}

mod introspection {
    pub mod interface;
    pub mod src5;
}

pub mod signer {
    mod eip191;
    pub mod signer_signature;
    mod webauthn;
}

mod outside_execution {
    pub mod interface;
    pub mod outside_execution;
    mod outside_execution_hash;
}

mod multisig_account {
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
}

mod multiowner_account {
    mod account_interface;
    pub mod argent_account;
    pub mod events;
    mod guardian_manager;
    mod owner_manager;
    pub mod recovery;
    mod replace_owners_message;
    mod signer_storage_linked_set;
    pub mod upgrade_migration;
}

mod utils {
    pub mod array_ext;
    pub mod asserts;
    pub mod bytes;
    pub mod calls;
    pub mod hashing;
    pub mod linked_set;
    pub mod linked_set_with_head;
    pub mod serialization;
    pub mod transaction_version;
}

mod mocks {
    //     mod future_argent_account;
//     mod future_argent_multisig;
//     mod linked_set_mock;
//     mod mock_dapp;
//     mod multiowner_mock;
//     mod multisig_mocks;
//     mod recovery_mocks;
//     mod signature_verifier;
//     mod src5_mocks;
}

mod session {
    pub mod interface;
    pub mod session;
    mod session_hash;
}

pub mod offchain_message {
    pub mod interface;
    pub mod precalculated_hashing;
}

