use lib::Version;
use account::{Escape, EscapeStatus};

#[starknet::interface]
trait IArgentAccount<TContractState> {
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: felt252,
        guardian: felt252
    ) -> felt252;
    // External

    /// @notice Changes the owner
    /// Must be called by the account and authorised by the owner and a guardian (if guardian is set).
    /// @param new_owner New owner address
    /// @param signature_r Signature R from the new owner 
    /// @param signature_S Signature S from the new owner 
    /// Signature is required to prevent changing to an address which is not in control of the user
    /// Signature is the Signed Message of this hash:
    /// hash = pedersen(0, (change_owner selector, chainid, contract address, old_owner))
    fn change_owner(
        ref self: TContractState, new_owner: felt252, signature_r: felt252, signature_s: felt252
    );

    /// @notice Changes the guardian
    /// Must be called by the account and authorised by the owner and a guardian (if guardian is set).
    /// @param new_guardian The address of the new guardian, or 0 to disable the guardian
    /// @dev can only be set to 0 if there is no guardian backup set
    fn change_guardian(ref self: TContractState, new_guardian: felt252);

    /// @notice Changes the backup guardian
    /// Must be called by the account and authorised by the owner and a guardian (if guardian is set).
    /// @param new_guardian_backup The address of the new backup guardian, or 0 to disable the backup guardian
    fn change_guardian_backup(ref self: TContractState, new_guardian_backup: felt252);

    /// @notice Triggers the escape of the owner when it is lost or compromised.
    /// Must be called by the account and authorised by just a guardian.
    /// Cannot override an ongoing escape of the guardian.
    /// @param new_owner The new account owner if the escape completes
    /// @dev This method assumes that there is a guardian, and that `_newOwner` is not 0.
    /// This must be guaranteed before calling this method, usually when validating the transaction.
    fn trigger_escape_owner(ref self: TContractState, new_owner: felt252);

    /// @notice Triggers the escape of the guardian when it is lost or compromised.
    /// Must be called by the account and authorised by the owner alone.
    /// Can override an ongoing escape of the owner.
    /// @param new_guardian The new account guardian if the escape completes
    /// @dev This method assumes that there is a guardian, and that `new_guardian` can only be 0
    /// if there is no guardian backup.
    /// This must be guaranteed before calling this method, usually when validating the transaction
    fn trigger_escape_guardian(ref self: TContractState, new_guardian: felt252);

    /// @notice Completes the escape and changes the owner after the security period
    /// Must be called by the account and authorised by just a guardian
    /// @dev This method assumes that there is a guardian, and that the there is an escape for the owner.
    /// This must be guaranteed before calling this method, usually when validating the transaction.
    fn escape_owner(ref self: TContractState);

    /// @notice Completes the escape and changes the guardian after the security period
    /// Must be called by the account and authorised by just the owner
    /// @dev This method assumes that there is a guardian, and that the there is an escape for the guardian.
    /// This must be guaranteed before calling this method. Usually when validating the transaction.
    fn escape_guardian(ref self: TContractState);

    /// @notice Cancels an ongoing escape if any.
    /// Must be called by the account and authorised by the owner and a guardian (if guardian is set).
    fn cancel_escape(ref self: TContractState);

    // Views
    fn get_owner(self: @TContractState) -> felt252;
    fn get_guardian(self: @TContractState) -> felt252;
    fn get_guardian_backup(self: @TContractState) -> felt252;
    fn get_escape(self: @TContractState) -> Escape;
    fn get_version(self: @TContractState) -> Version;
    fn get_name(self: @TContractState) -> felt252;
    fn get_guardian_escape_attempts(self: @TContractState) -> u32;
    fn get_owner_escape_attempts(self: @TContractState) -> u32;

    /// Current escape if any, and its status
    fn get_escape_and_status(self: @TContractState) -> (Escape, EscapeStatus);
}

/// Deprecated methods for compatibility reasons
#[starknet::interface]
trait IDeprecatedArgentAccount<TContractState> {
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn isValidSignature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
}
