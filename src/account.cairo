use argent::signer::signer_signature::Signer;
use starknet::account::Call;

pub const SRC5_ACCOUNT_INTERFACE_ID: felt252 = 0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd;
pub const SRC5_ACCOUNT_INTERFACE_ID_OLD_1: felt252 = 0xa66bd575;
pub const SRC5_ACCOUNT_INTERFACE_ID_OLD_2: felt252 = 0x3943f10f;

#[derive(Serde, Copy, Drop)]
pub struct Version {
    pub major: u8,
    pub minor: u8,
    pub patch: u8,
}

#[starknet::interface]
pub trait IAccount<TContractState> {
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>);

    /// @notice Checks whether a given signature for a given hash is valid
    /// @dev Warning: To guarantee the signature cannot be replayed in other accounts or other chains, the data hashed
    /// must be unique to the account and the chain.
    /// This is true today for starknet transaction signatures and for SNIP-12 signatures but might not be true for
    /// other types of signatures @param hash The hash of the data to sign
    /// @param signature The signature to validate
    /// @return The shortstring 'VALID' when the signature is valid, 0 if the signature doesn't match the hash
    /// @dev it can also panic if the signature is not in a valid format
    fn is_valid_signature(self: @TContractState, hash: felt252, signature: Array<felt252>) -> felt252;
}

#[starknet::interface]
pub trait IArgentAccount<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<Signer>,
    ) -> felt252;
    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
}

/// Deprecated methods for compatibility reasons
#[starknet::interface]
pub trait IDeprecatedArgentAccount<TContractState> {
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    /// For compatibility reasons this function returns 1 when the signature is valid, and panics otherwise
    fn isValidSignature(self: @TContractState, hash: felt252, signatures: Array<felt252>) -> felt252;
}


impl VersionPartialOrd of PartialOrd<Version> {
    fn lt(lhs: Version, rhs: Version) -> bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major;
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor;
        }
        return lhs.patch < rhs.patch;
    }
}
