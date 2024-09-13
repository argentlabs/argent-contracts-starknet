mod test_asserts;
mod test_comp_multisig;
mod test_comp_recovery_external;
mod test_comp_recovery_threshold;
mod test_comp_signer_list;
mod test_comp_src5;
mod test_eip191;
mod test_linked_set;
mod test_offchain_hashing;
mod test_secp256k1;
mod test_secp256r1;
mod test_transaction_version;

// Re-export the test setup functions to have them all available in one place
use setup::{
    account_test_setup::{
        ITestArgentAccountDispatcherTrait, initialize_account_with, initialize_account,
        initialize_account_without_guardian
    },
    multiowner_account_test_setup::{
        ITestMultiOwnerAccountDispatcherTrait, initialize_mo_account_with, initialize_mo_account,
        initialize_mo_account_without_guardian
    },
    utils::{to_starknet_signatures, to_starknet_signer_signatures, Felt252TryIntoStarknetSigner},
    constants::{
        ARGENT_ACCOUNT_ADDRESS, KeyAndSig, GUARDIAN, OWNER, GUARDIAN_BACKUP, MULTISIG_OWNER, WRONG_OWNER,
        WRONG_GUARDIAN, tx_hash, SIGNER_1, SIGNER_2, SIGNER_3, SIGNER_4
    },
    multisig_test_setup::{
        ITestArgentMultisigDispatcherTrait, initialize_multisig_with_one_signer, initialize_multisig_with,
        initialize_multisig, declare_multisig
    }
};

mod argent_account {
    mod test_argent_account;
    mod test_escape;
    mod test_signatures;
}

mod multi_owner_account {
    mod test_multi_owner_account;
}

mod multisig {
    mod test_add_signers;
    mod test_multisig_account;
    mod test_remove_signers;
    mod test_replace_signer;
    mod test_signing;
}

mod setup {
    mod account_test_setup;
    mod constants;
    mod multiowner_account_test_setup;
    mod multisig_test_setup;
    mod utils;
}

mod webauthn {
    mod test_webauthn_bytes;
    mod test_webauthn_sha256;
    mod test_webauthn_validation;
}
