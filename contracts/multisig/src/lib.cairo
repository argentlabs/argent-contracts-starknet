use lib::Version;

#[abi]
trait IUpgradeTarget {
    /// @dev This will be called on the new implementation when there is an upgrade to it
    /// @param previous_version The previous account version
    /// @param calldata Data passed to this function
    fn execute_after_upgrade(previous_version: Version, data: Array<felt252>) -> Array::<felt252>;
}


mod argent_multisig_account;
use argent_multisig_account::ArgentMultisigAccount;

mod argent_multisig_storage;
use argent_multisig_storage::MultisigStorage;

// Structures 

mod signer_signature;
use signer_signature::SignerSignature;
use signer_signature::deserialize_array_signer_signature;
use signer_signature::SignerSignatureSize;

#[cfg(test)]
mod tests;
