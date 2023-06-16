use lib::Version;

// #[starknet::interface]
// trait IUpgradeTarget {
//     /// @dev Logic to execute after an upgrade.
//     /// Can only be called by the account after a call to `upgrade`.
//     /// @param data Generic call data that can be passed to the method for future upgrade logic
//     fn execute_after_upgrade(data: Array<felt252>) -> Array<felt252>;
// }

mod argent_multisig;
use argent_multisig::ArgentMultisig;

// mod argent_multisig_storage;
// use argent_multisig_storage::MultisigStorage;

// Structures 

mod signer_signature;
use signer_signature::SignerSignature;
use signer_signature::deserialize_array_signer_signature;

#[cfg(test)]
mod tests;

