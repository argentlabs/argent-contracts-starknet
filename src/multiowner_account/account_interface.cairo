use argent::account::Version;
use argent::multiowner_account::owner_alive::OwnerAliveSignature;
use argent::multiowner_account::recovery::Escape;
use argent::recovery::EscapeStatus;
use argent::signer::signer_signature::Signer;

#[starknet::interface]
pub trait IArgentMultiOwnerAccount<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: Signer,
        guardian: Option<Signer>,
    ) -> felt252;

    /// @notice Updates the security period for escapes
    /// @param new_security_period Delay in seconds before an escape can be completed. The escape will expire after the
    /// same delay.
    /// @dev Must be >= 10 minutes
    /// @dev Must be called by the account and authorized by one owner and one guardian (if set)
    /// @dev Reverts if there is an ongoing escape
    fn set_escape_security_period(ref self: TContractState, new_security_period: u64);

    /// @notice Updates the account owners
    /// @param owner_guids_to_remove List of owner GUIDs to remove
    /// @param owners_to_add List of new owners to add
    /// @param owner_alive_signature Required when removing the transaction signer and no guardian exists. Must prove
    /// there is a valid owner after the change
    /// @dev Requires authorization from one owner and one guardian (if set)
    /// @dev Cancels any existing escape
    /// @dev Reverts if removing non-existent owners or adding duplicate owners
    /// @dev Reverts if there's any overlap between the owners to add and the owners to remove
    /// @dev Reverts if there are duplicates in the owners to add or remove
    fn change_owners(
        ref self: TContractState,
        owner_guids_to_remove: Array<felt252>,
        owners_to_add: Array<Signer>,
        owner_alive_signature: Option<OwnerAliveSignature>,
    );

    /// @notice Updates the account guardians
    /// @param guardian_guids_to_remove List of guardian GUIDs to remove
    /// @param guardians_to_add List of new guardians to add
    /// @dev Must be called by the account and authorized by one owner and one guardian (if set)
    /// @dev Cancels any existing escape
    /// @dev Reverts if removing non-existent guardians or adding duplicate guardians
    /// @dev Reverts if there's any overlap between the guardians to add and the guardians to remove
    /// @dev Reverts if there are duplicates in the guardians to add or remove
    fn change_guardians(
        ref self: TContractState, guardian_guids_to_remove: Array<felt252>, guardians_to_add: Array<Signer>,
    );

    /// @notice Initiates escape process to replace all owners. Useful if they are lost or compromised
    /// @param new_owner The new owner that will replace all existing owners if escape completes
    /// @dev Must be called by the account and authorized by one guardian
    /// @dev Reverts if there's an ongoing guardian escape
    fn trigger_escape_owner(ref self: TContractState, new_owner: Signer);

    /// @notice Initiates escape process to replace or remove guardians. Useful if they are lost or compromised
    /// @param new_guardian The new guardian that will replace all existing guardians if escape completes, or None to
    /// remove all guardians
    /// @dev Must be called by the account and authorized by one owner
    /// @dev Can override an ongoing owner escape
    /// @dev Reverts if there are no guardians currently set
    fn trigger_escape_guardian(ref self: TContractState, new_guardian: Option<Signer>);

    /// @notice Completes the owner escape, replacing all owners with the new owner from trigger_escape_owner
    /// @dev Must be called by the account and authorized by one guardian
    /// @dev Reverts if there is no owner escape in 'EscapeStatus.Ready' state
    fn escape_owner(ref self: TContractState);

    /// @notice Completes the guardian escape, replacing all guardians with the new guardian from
    /// trigger_escape_guardian. Or leaving the account without guardians if the new guardian is None.
    /// @dev Must be called by the account and authorized by one owner
    /// @dev Reverts if there is no guardian escape in 'EscapeStatus.Ready' state
    fn escape_guardian(ref self: TContractState);

    /// @notice Cancels any ongoing escape process
    /// @dev Must be called by the account and authorized by one owner and one guardian (if set)
    /// @dev Reverts if no escape is in progress
    fn cancel_escape(ref self: TContractState);

    // Views

    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;

    fn get_escape(self: @TContractState) -> Escape;
    fn get_last_owner_trigger_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_trigger_escape_attempt(self: @TContractState) -> u64;
    fn get_last_owner_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_escape_attempt(self: @TContractState) -> u64;

    /// @return (escape, status) Current escape configuration and its status
    fn get_escape_and_status(self: @TContractState) -> (Escape, EscapeStatus);

    /// @return Current security period for escapes in seconds
    fn get_escape_security_period(self: @TContractState) -> u64;
}

