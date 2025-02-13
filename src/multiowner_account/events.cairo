use argent::signer::signer_signature::Signer;

/// @notice Deprecated: Use AccountCreatedGuid instead
/// @dev This is only emitted for the owner and then guardian when they of type SignerType::Starknet
/// @dev Emitted exactly once when the account is initialized
/// @param owner The owner starknet pubkey
/// @param guardian The guardian starknet pubkey or 0 if there's no guardian
#[derive(Drop, starknet::Event)]
pub struct AccountCreated {
    #[key]
    pub owner: felt252,
    pub guardian: felt252,
}

/// @notice Emitted on initialization with the the owner and guardian (or 0 if none) guid's
/// @dev Emitted exactly once when the account is initialized
/// @dev Emitted exactly once when the account is initialized
/// @param owner_guid GUID of the owner
/// @param guardian_guid GUID of the guardian, or 0 if none
#[derive(Drop, starknet::Event)]
pub struct AccountCreatedGuid {
    #[key]
    pub owner_guid: felt252,
    pub guardian_guid: felt252,
}

/// Deprecated: This event will likely be removed in the future
/// @notice Emitted when the account executes a transaction
/// @param hash The transaction hash
#[derive(Drop, starknet::Event)]
pub struct TransactionExecuted {
    #[key]
    pub hash: felt252,
}

/// @notice Links a signer to its GUID for future reference as the account is not storing all the Signer data
/// @dev This is the only way to get the Signer data from a GUID
/// @param signer_guid Identified derived from the signer
/// @param signer The Signer details
#[derive(Drop, Serde, starknet::Event)]
pub struct SignerLinked {
    #[key]
    pub signer_guid: felt252,
    pub signer: Signer,
}

/// @notice Emitted when an owner is added
/// @dev Also emitted during account creation and when upgrading from a version that didn't emit the event
/// @param new_owner_guid GUID of the new owner
#[derive(Drop, starknet::Event)]
pub struct OwnerAddedGuid {
    #[key]
    pub new_owner_guid: felt252,
}

/// @notice Emitted when an owner is removed
/// @param removed_owner_guid GUID of the removed owner
#[derive(Drop, starknet::Event)]
pub struct OwnerRemovedGuid {
    #[key]
    pub removed_owner_guid: felt252,
}

/// @notice Emitted when a guardian is added
/// @dev Could also emitted during account creation and when upgrading from older versions that didn't emit the event
/// @param new_guardian_guid GUID of the new guardian
#[derive(Drop, starknet::Event)]
pub struct GuardianAddedGuid {
    #[key]
    pub new_guardian_guid: felt252,
}

/// @notice Emitted when a guardian is removed
#[derive(Drop, starknet::Event)]
pub struct GuardianRemovedGuid {
    #[key]
    pub removed_guardian_guid: felt252,
}

/// @notice Owner escape initiated by a guardian
/// @param ready_at Timestamp when escape becomes ready for completion
/// @param new_owner_guid GUID of the proposed new owner
#[derive(Drop, starknet::Event)]
pub struct EscapeOwnerTriggeredGuid {
    pub ready_at: u64,
    pub new_owner_guid: felt252,
}

/// @notice Guardian escape initiated by an owner
/// @param ready_at Timestamp when escape becomes ready for completion
/// @param new_guardian_guid GUID of the proposed new guardian, or 0 to remove guardians
#[derive(Drop, starknet::Event)]
pub struct EscapeGuardianTriggeredGuid {
    pub ready_at: u64,
    pub new_guardian_guid: felt252,
}

/// @notice Owner escape completed successfully
/// @param new_owner_guid GUID of the new owner
#[derive(Drop, starknet::Event)]
pub struct OwnerEscapedGuid {
    pub new_owner_guid: felt252,
}

/// @notice Guardian escape completed successfully
/// @param new_guardian_guid GUID of the new guardian, or 0 if all guardians were removed
#[derive(Drop, starknet::Event)]
pub struct GuardianEscapedGuid {
    pub new_guardian_guid: felt252,
}

/// @notice Emitted when an escape is canceled
#[derive(Drop, starknet::Event)]
pub struct EscapeCanceled {}

/// @notice The security period for the escape has been changed
/// @param escape_security_period the new security for the escape in seconds
#[derive(Drop, starknet::Event)]
pub struct EscapeSecurityPeriodChanged {
    pub escape_security_period: u64,
}
