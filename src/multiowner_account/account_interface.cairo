use argent::account::interface::Version;
use argent::multiowner_account::recovery::Escape;
use argent::recovery::{EscapeStatus};
use argent::signer::signer_signature::{Signer, SignerType, SignerSignature};

#[starknet::interface]
trait IArgentMultiOwnerAccount<TContractState> {
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

    /// @notice Removes all owners from this account and adds a new one
    /// @dev Must be called by the account and authorized by 1 owner and a guardian (if guardian is set)
    /// @param new_single_owner SignerSignature of the new owner
    /// Required to prevent changing to a signer which is not in control of the user
    /// It is the signature of the SNIP-12 V1 compliant object ReplaceOwnersWithOne
    /// @param signature_expiration Signature expiration timestamp
    /// cannot be in the past: before current timestamp
    /// cannot be too far in the future: current timestamp + 1 DAY in seconds
    /// @dev It will cancel any existing escape
    fn reset_owners(ref self: TContractState, new_single_owner: SignerSignature, signature_expiration: u64);

    /// @notice Adds new owners to this account
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @dev It will cancel any existing escape
    fn add_owners(ref self: TContractState, new_owners: Array<Signer>);

    /// @notice Removes owners from this account
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @dev The owner signing this call cannot be removed
    /// @dev It will cancel any existing escape
    fn remove_owners(ref self: TContractState, owner_guids_to_remove: Array<felt252>);

    /// @notice Adds new guardians to this account
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @dev It will cancel any existing escape
    fn add_guardians(ref self: TContractState, new_guardians: Array<Signer>);

    /// @notice Removes guardians from this account
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @dev It will cancel any existing escape
    fn remove_guardians(ref self: TContractState, guardian_guids_to_remove: Array<felt252>);

    /// @notice Removes all guardians and optionally adds a new one
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @param new_guardian The address of the new guardian, or None to disable the guardian
    fn reset_guardians(ref self: TContractState, new_guardian: Option<Signer>);

    /// @notice Triggers the escape of the owner when it is lost or compromised
    /// @dev Must be called by the account and authorized by just a guardian
    /// @dev This function assumes that there is a guardian
    /// @dev Cannot override an ongoing escape of the guardian
    /// @param new_owner The new account owner if the escape completes
    /// This must be guaranteed before calling this method, usually when validating the transaction
    fn trigger_escape_owner(ref self: TContractState, new_owner: Signer);

    /// @notice Triggers the escape of the guardian when it is lost or compromised
    /// @dev Can override an ongoing escape of the owner
    /// @dev Must be called by the account and authorized by the owner alone
    /// @dev This function assumes that there is at least one guardian
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

    fn get_escape(self: @TContractState) -> Escape;
    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
    fn get_last_owner_trigger_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_trigger_escape_attempt(self: @TContractState) -> u64;
    fn get_last_owner_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_escape_attempt(self: @TContractState) -> u64;

    /// Current escape if any, and its status
    fn get_escape_and_status(self: @TContractState) -> (Escape, EscapeStatus);
    /// Reads the current security period used for escapes
    fn get_escape_security_period(self: @TContractState) -> u64;
}
