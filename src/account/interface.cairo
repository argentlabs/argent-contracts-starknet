use argent::recovery::interface::{LegacyEscape, EscapeStatus};
use argent::signer::signer_signature::{Signer, SignerType, SignerSignature};
use starknet::account::Call;

const SRC5_ACCOUNT_INTERFACE_ID: felt252 = 0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd;
const SRC5_ACCOUNT_INTERFACE_ID_OLD_1: felt252 = 0xa66bd575;
const SRC5_ACCOUNT_INTERFACE_ID_OLD_2: felt252 = 0x3943f10f;

#[derive(Serde, Drop)]
struct Version {
    major: u8,
    minor: u8,
    patch: u8,
}

#[starknet::interface]
trait IAccount<TContractState> {
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;

    /// @notice Checks whether a given signature for a given hash is valid
    /// @dev Warning: To guarantee the signature cannot be replayed in other accounts or other chains, the data hashed must be unique to the account and the chain.
    /// This is true today for starknet transaction signatures and for SNIP-12 signatures but might not be true for other types of signatures
    /// @param hash The hash of the data to sign
    /// @param signature The signature to validate
    /// @return The shortstring 'VALID' when the signature is valid, 0 if the signature doesn't match the hash
    /// @dev it can also panic if the signature is not in a valid format
    fn is_valid_signature(self: @TContractState, hash: felt252, signature: Array<felt252>) -> felt252;
}

#[starknet::interface]
trait IArgentAccount<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        new_threshold: usize,
        signers: Array<Signer>
    ) -> felt252;
    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
}

#[starknet::interface]
trait IArgentUserAccount<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: Signer,
        guardian: Option<Signer>
    ) -> felt252;

    /// @notice Changes the security period used for escapes
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @param new_security_period new delay in seconds before the escape can be completed. Must be >= 10 minutes
    fn set_escape_security_period(ref self: TContractState, new_security_period: u64);

    /// @notice Changes the owner
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @param signer_signature SignerSignature of the new owner 
    /// Required to prevent changing to an address which is not in control of the user
    /// is the signature of the pedersen hashed array: 
    /// [change_owner_selector, chain_id, account_address, old_owner_guid]
    fn change_owner(ref self: TContractState, signer_signature: SignerSignature);

    /// @notice Changes the guardian
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @dev can only be set to 0 if there is no guardian backup set
    /// @param new_guardian The address of the new guardian, or 0 to disable the guardian
    fn change_guardian(ref self: TContractState, new_guardian: Option<Signer>);

    /// @notice Changes the backup guardian
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @param new_guardian_backup The address of the new backup guardian, or 0 to disable the backup guardian
    fn change_guardian_backup(ref self: TContractState, new_guardian_backup: Option<Signer>);

    /// @notice Triggers the escape of the owner when it is lost or compromised
    /// @dev Must be called by the account and authorized by just a guardian
    /// @dev This function assumes that there is a guardian, and that `new_owner` is not 0
    /// @dev Cannot override an ongoing escape of the guardian
    /// @param new_owner The new account owner if the escape completes
    /// This must be guaranteed before calling this method, usually when validating the transaction
    fn trigger_escape_owner(ref self: TContractState, new_owner: Signer);

    /// @notice Triggers the escape of the guardian when it is lost or compromised
    /// @dev Can override an ongoing escape of the owner
    /// @dev Must be called by the account and authorized by the owner alone
    /// @dev This function assumes that there is a guardian, and that `new_guardian` can only be 0
    /// if there is no guardian backup
    /// This must be guaranteed before calling this method, usually when validating the transaction
    /// @param new_guardian The new account guardian if the escape completes
    fn trigger_escape_guardian(ref self: TContractState, new_guardian: Option<Signer>);

    /// @notice Completes the escape and changes the owner after the security period
    /// @dev Must be called by the account and authorized by just a guardian
    /// @dev This function assumes that there is a guardian, and that the there is an escape for the owner
    /// This must be guaranteed before calling this method, usually when validating the transaction
    fn escape_owner(ref self: TContractState);

    /// @notice Completes the escape and changes the guardian after the security period
    /// @dev Must be called by the account and authorized by just the owner
    /// @dev This function assumes that there is a guardian, and that the there is an escape for the guardian
    /// @dev This must be guaranteed before calling this method. Usually when validating the transaction
    fn escape_guardian(ref self: TContractState);

    /// @notice Cancels an ongoing escape if any
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    fn cancel_escape(ref self: TContractState);

    // Views

    /// @notice Returns the public key if the requested role is Starknet, Eip191 or Secp256k1 and panic for other types
    fn get_owner(self: @TContractState) -> felt252;
    fn get_owner_guid(self: @TContractState) -> felt252;
    fn get_owner_type(self: @TContractState) -> SignerType;
    /// @notice Returns the starknet pub key or `0` if there's no guardian
    fn get_guardian(self: @TContractState) -> felt252;
    fn is_guardian(self: @TContractState, guardian: Signer) -> bool;
    fn get_guardian_guid(self: @TContractState) -> Option<felt252>;
    /// @notice Returns `Starknet` if there's a guardian, `None` otherwise
    fn get_guardian_type(self: @TContractState) -> Option<SignerType>;
    /// @notice Returns `0` if there's no guardian backup, the public key if the requested role is Starknet, Eip191 or Secp256k1 and panic for other types
    fn get_guardian_backup(self: @TContractState) -> felt252;
    fn get_guardian_backup_guid(self: @TContractState) -> Option<felt252>;
    /// @notice Returns the backup guardian type if there's any backup guardian
    fn get_guardian_backup_type(self: @TContractState) -> Option<SignerType>;
    fn get_escape(self: @TContractState) -> LegacyEscape;
    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
    fn get_last_owner_trigger_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_trigger_escape_attempt(self: @TContractState) -> u64;
    fn get_last_owner_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_escape_attempt(self: @TContractState) -> u64;

    /// Current escape if any, and its status
    fn get_escape_and_status(self: @TContractState) -> (LegacyEscape, EscapeStatus);
    /// Reads the current security period used for escapes
    fn get_escape_security_period(self: @TContractState) -> u64;
}

/// Deprecated methods for compatibility reasons
#[starknet::interface]
trait IDeprecatedArgentAccount<TContractState> {
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    /// For compatibility reasons this function returns 1 when the signature is valid, and panics otherwise
    fn isValidSignature(self: @TContractState, hash: felt252, signatures: Array<felt252>) -> felt252;
}
