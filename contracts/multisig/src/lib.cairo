mod interface;
use interface::IArgentMultisig;
use interface::IDeprecatedArgentMultisig;

mod argent_multisig;
use argent_multisig::ArgentMultisig;

// Structures 

mod signer_signature;
use signer_signature::SignerSignature;
use signer_signature::deserialize_array_signer_signature;

#[cfg(test)]
mod tests;

