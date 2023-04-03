mod spans;

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
