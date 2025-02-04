pub mod recovery;

mod upgrade {
    pub mod interface;
    pub mod upgrade;
}

pub mod account {
    pub mod interface;
}

pub mod introspection {
    pub mod interface;
    pub mod src5;
}

pub mod signer {
    pub mod eip191;
    pub mod signer_signature;
    pub mod webauthn;
}

pub mod outside_execution {
    pub mod interface;
    pub mod outside_execution;
    pub mod outside_execution_hash;
}

pub mod multisig_account {
    mod multisig_account;
    mod upgrade_migration;
    pub mod external_recovery {
        pub mod external_recovery;
        pub mod interface;
        mod packing;
    }
    pub mod signer_manager {
        pub mod interface;
        pub mod signer_manager;
    }
}

pub mod multiowner_account {
    pub mod account_interface;
    pub mod argent_account;
    pub mod events;
    pub mod guardian_manager;
    pub mod owner_alive;
    pub mod owner_manager;
    pub mod recovery;
    pub mod signer_storage_linked_set;
    pub mod upgrade_migration;
}

pub mod utils {
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

pub mod mocks {
    mod future_argent_account;
    mod future_argent_multisig;
    pub mod linked_set_mock;
    mod mock_dapp;
    mod multiowner_mock;
    pub mod multisig_mocks;
    mod recovery_mocks;
    mod signature_verifier;
    pub mod src5_mocks;
}

pub mod session {
    pub mod interface;
    pub mod session;
    pub mod session_hash;
}

pub mod offchain_message {
    pub mod interface;
    pub mod precalculated_hashing;
}

