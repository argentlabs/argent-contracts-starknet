mod test_asserts;
mod test_comp_multisig;
mod test_comp_recovery_external;
mod test_comp_src5;
mod test_linked_set;
mod test_linked_set_with_head;
mod test_offchain_hashing;
mod test_signatures;
mod test_transaction_version;
mod test_version;

mod argent_account {
    mod test_argent_account;
    mod test_change_guardians;
    mod test_change_owners;
    mod test_escape;
    mod test_i_account;
    mod test_sessions;
    mod test_signatures;
}

mod multisig {
    mod test_add_signers;
    mod test_multisig_account;
    mod test_remove_signers;
    mod test_replace_signer;
    mod test_signing;
}

mod setup {
    pub mod argent_account_setup;
    pub mod multisig_test_setup;
    pub mod signers;
}

mod webauthn {
    mod test_webauthn_bytes;
    mod test_webauthn_validation;
}

// Re-export the test setup functions to have them all available in one place
use setup::{
    argent_account_setup::{
        ArgentAccountSetup, ArgentAccountWithoutGuardianSetup, ITestArgentAccountDispatcherTrait, initialize_account,
        initialize_account_with_owners_and_guardians, initialize_account_without_guardian,
    },
    multisig_test_setup::{
        ITestArgentMultisigDispatcherTrait, MultisigSetup, declare_multisig, initialize_multisig_m_of_n,
    },
    signers::{
        Eip191KeyPair, Secp256k1KeyPair, Secp256r1KeyPair, SignerKeyPair, SignerKeyPairImpl, SignerKeyPairTestTrait,
        StarknetKeyPair,
    },
};
