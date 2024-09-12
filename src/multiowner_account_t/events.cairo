use argent::signer::signer_signature::Signer;

/// @notice Deprecated. This is only emitted for the owner and then guardian when they of type
/// SignerType::Starknet @dev Emitted exactly once when the account is initialized
/// @param owner The owner starknet pubkey
/// @param guardian The guardian starknet pubkey or 0 if there's no guardian
#[derive(Drop, starknet::Event)]
struct AccountCreated {
    #[key]
    owner: felt252,
    guardian: felt252
}

/// @notice Emitted on initialization with the guids of the owner and the guardian (or 0 if
/// none)
/// @dev Emitted exactly once when the account is initialized
/// @param owner The owner guid
/// @param guardian The guardian guid or 0 if there's no guardian
#[derive(Drop, starknet::Event)]
struct AccountCreatedGuid {
    #[key]
    owner_guid: felt252,
    guardian_guid: felt252
}

/// @notice Emitted when the account executes a transaction
/// @param hash The transaction hash
/// @param response The data returned by the methods called
#[derive(Drop, starknet::Event)]
struct TransactionExecuted {
    #[key]
    hash: felt252,
    response: Span<Span<felt252>>
}

/// @notice A new signer was linked
/// @dev This is the only way to get the signer struct knowing a only guid
/// @param signer_guid the guid of the signer derived from the signer
/// @param signer the signer being added
#[derive(Drop, Serde, starknet::Event)]
struct SignerLinked {
    #[key]
    signer_guid: felt252,
    signer: Signer,
}


/// Emitted when an account owner is added, including when the account is created.
#[derive(Drop, starknet::Event)]
struct OwnerAddedGuid {
    #[key]
    new_owner_guid: felt252,
}

/// Emitted when an an account owner is removed
#[derive(Drop, starknet::Event)]
struct OwnerRemovedGuid {
    #[key]
    removed_owner_guid: felt252,
}


/// @notice Owner escape was triggered by the guardian
/// @param ready_at when the escape can be completed
/// @param new_owner_guid new guid to be set after the security period
#[derive(Drop, starknet::Event)]
struct EscapeOwnerTriggeredGuid {
    ready_at: u64,
    new_owner_guid: felt252
}

/// @notice Guardian escape was triggered by the owner
/// @param ready_at when the escape can be completed
/// @param new_guardian_guid to be set after the security period. O if the guardian will be
/// removed
#[derive(Drop, starknet::Event)]
struct EscapeGuardianTriggeredGuid {
    ready_at: u64,
    new_guardian_guid: felt252
}

/// @notice Owner escape was completed and there is a new account owner
/// @param new_owner_guid new owner guid
#[derive(Drop, starknet::Event)]
struct OwnerEscapedGuid {
    new_owner_guid: felt252
}

/// @notice Guardian escape was completed and there is a new account guardian
/// @param new_guardian_guid guid of the new guardian or 0 if it was removed
#[derive(Drop, starknet::Event)]
struct GuardianEscapedGuid {
    new_guardian_guid: felt252
}

/// @notice An ongoing escape was canceled
#[derive(Drop, starknet::Event)]
struct EscapeCanceled {}

/// @notice Deprecated from v0.4.0. This is only emitted if the new owner is a starknet key
/// @notice The account owner was changed
/// @param new_owner new owner address
#[derive(Drop, starknet::Event)]
struct OwnerChanged {
    new_owner: felt252
}

/// @notice The account owner was changed
/// @param new_owner_guid new owner guid
#[derive(Drop, starknet::Event)]
struct OwnerChangedGuid {
    new_owner_guid: felt252
}

/// @notice Deprecated from v0.4.0. This is only emitted if the new guardian is empty or a
/// starknet key @notice The account guardian was changed or removed
/// @param new_guardian address of the new guardian or 0 if it was removed
#[derive(Drop, starknet::Event)]
struct GuardianChanged {
    new_guardian: felt252
}

/// @notice The account guardian was changed or removed
/// @param new_guardian_guid address of the new guardian or 0 if it was removed
#[derive(Drop, starknet::Event)]
struct GuardianChangedGuid {
    new_guardian_guid: felt252
}

/// @notice Deprecated from v0.4.0. This is only emitted if the new guardian backup is empty or
/// a starknet key @notice The account backup guardian was changed or removed
/// @param new_guardian_backup address of the backup guardian or 0 if it was removed
#[derive(Drop, starknet::Event)]
struct GuardianBackupChanged {
    new_guardian_backup: felt252
}

/// @notice The account backup guardian was changed or removed
/// @param new_guardian_backup_guid guid of the backup guardian or 0 if it was removed
#[derive(Drop, starknet::Event)]
struct GuardianBackupChangedGuid {
    new_guardian_backup_guid: felt252
}


/// @notice The security period for the escape was update
/// @param escape_security_period the new security for the escape in seconds
#[derive(Drop, starknet::Event)]
struct EscapeSecurityPeriodChanged {
    escape_security_period: u64,
}
