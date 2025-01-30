mod test_asserts;
mod test_comp_multisig;
mod test_comp_recovery_external;
mod test_comp_src5;
mod test_eip191;
mod test_linked_set;
mod test_offchain_hashing;
mod test_secp256k1;
mod test_secp256r1;
mod test_transaction_version;
mod test_version;

mod argent_account {
    mod test_argent_account;
    mod test_escape;
    mod test_signatures;
}

// mod multisig {
//     mod test_add_signers;
//     mod test_multisig_account;
//     mod test_remove_signers;
//     mod test_replace_signer;
//     mod test_signing;
// }

mod setup {
    pub mod argent_account_setup;
    pub mod constants;
    pub mod multisig_test_setup;
    pub mod utils;
}

mod webauthn {
    mod test_webauthn_bytes;
    mod test_webauthn_validation;
}

// Re-export the test setup functions to have them all available in one place
use setup::{
    argent_account_setup::{
        ITestArgentAccountDispatcherTrait, initialize_account, initialize_account_with,
        initialize_account_without_guardian,
    },
    constants::{
        ARGENT_ACCOUNT_ADDRESS, GUARDIAN, KeyAndSig, MULTISIG_OWNER, OWNER, SIGNER_1, SIGNER_2, SIGNER_3, SIGNER_4,
        TX_HASH, WRONG_GUARDIAN, WRONG_OWNER,
    },
    multisig_test_setup::{
        ITestArgentMultisigDispatcherTrait, declare_multisig, initialize_multisig, initialize_multisig_with,
        initialize_multisig_with_one_signer,
    },
    utils::{Felt252TryIntoStarknetSigner, to_starknet_signatures, to_starknet_signer_signatures},
};
