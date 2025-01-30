use argent::account::interface::Version;
use argent::multiowner_account::recovery::Escape;
use argent::recovery::{EscapeStatus};
use argent::signer::signer_signature::{Signer, SignerSignature, SignerType};

#[starknet::interface]
trait IArgentMultiOwnerAccount<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: Signer,
        guardian: Option<Signer>,
    ) -> felt252;

    /// @notice Changes the security period used for escapes
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @dev Will revert if there is an ongoing escape
    /// @param new_security_period new delay in seconds before the escape can be completed. Must be >= 10 minutes
    fn set_escape_security_period(ref self: TContractState, new_security_period: u64);


    /// @notice Manage the owners of this account by adding and/or removing them
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @param owner_guids_to_remove The list of owner guids to remove
    /// @param owners_to_add The list of owners to add
    /// @param owner_alive_signature Signature proving there is a valid owner after the change, required when this call
    /// will remove the owner that signed the transaction and there's no guardian
    /// @dev It will cancel any existing escape
    /// @dev Will revert if any of the guids to remove is not an owner
    /// @dev Will revert if any of the signers to add is already an owner
    fn change_owners(
        ref self: TContractState,
        owner_guids_to_remove: Array<felt252>,
        owners_to_add: Array<Signer>,
        owner_alive_signature: Option<OwnerAliveSignature>,
    );

    /// @notice Manage the guardians of this account by adding and/or removing them
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    /// @param guardian_guids_to_remove The list of guardian guids to remove
    /// @param guardians_to_add The list of guardians to add
    /// @dev It will cancel any existing escape
    /// @dev Will revert if any of the guids to remove is not a guardian
    /// @dev Will revert if any of the signers to add is already a guardian
    fn change_guardians(
        ref self: TContractState, guardian_guids_to_remove: Array<felt252>, guardians_to_add: Array<Signer>,
    );

    /// @notice Triggers the escape of the owner when it is lost or compromised
    /// @dev Must be called by the account and authorized by just a guardian
    /// @dev This function assumes the presence of a guardian
    /// This is ensured by the account during call validation.
    /// @dev Cannot override an ongoing escape of the guardian
    /// @param new_owner The new account owner for when escape completes
    fn trigger_escape_owner(ref self: TContractState, new_owner: Signer);

    /// @notice Triggers the escape of the guardian when it is lost or compromised
    /// @dev Can override an ongoing escape of the owner
    /// @dev Must be called by the account and authorized by the owner alone
    /// @dev This function assumes that there is at least one guardian
    /// This is ensured by the account during call validation.
    /// @param new_guardian The new account guardian or None if the owner wants to remove the guardian
    fn trigger_escape_guardian(ref self: TContractState, new_guardian: Option<Signer>);

    /// @notice Completes the escape and changes the owner. Can only be called after the security period has elapsed
    /// @dev Must be called by the account and authorized by just a guardian
    /// @dev This function assumes that there is a guardian, and that the there is an escape for the owner
    /// This is ensured by the account during call validation.
    fn escape_owner(ref self: TContractState);

    /// @notice Completes the escape and changes the guardian. Can only be called after the security period has elapsed
    /// @dev Must be called by the account and authorized by just the owner
    /// @dev This function assumes that there is a guardian, and that the there is an escape for the guardian
    /// This is ensured by the account during call validation.
    fn escape_guardian(ref self: TContractState);

    /// @notice Cancels an ongoing escape
    /// @dev Will revert if there is no ongoing escape
    /// @dev Must be called by the account and authorized by the owner and a guardian (if guardian is set)
    fn cancel_escape(ref self: TContractState);

    // Views

    /// @notice Returns the public key if the requested role is Starknet, Eip191 or Secp256k1 and panic for other types
    /// @dev Fails if there is more than one owner
    fn get_owner(self: @TContractState) -> felt252;
    fn get_owner_guid(self: @TContractState) -> felt252;
    fn get_owner_type(self: @TContractState) -> SignerType;

    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;

    fn get_escape(self: @TContractState) -> Escape;
    fn get_last_owner_trigger_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_trigger_escape_attempt(self: @TContractState) -> u64;
    fn get_last_owner_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_escape_attempt(self: @TContractState) -> u64;

    /// Current escape if any, and its status
    fn get_escape_and_status(self: @TContractState) -> (Escape, EscapeStatus);
    /// Reads the current security period used for escapes
    fn get_escape_security_period(self: @TContractState) -> u64;
}


///  Required to prevent changing to an owner which is not in control of the user
#[derive(Drop, Copy, Serde)]
struct OwnerAliveSignature {
    /// It is the signature of the SNIP-12 V1 compliant object OwnerAlive
    owner_signature: SignerSignature,
    /// in seconds. cannot be more than 24 hours in the future
    signature_expiration: u64,
}
