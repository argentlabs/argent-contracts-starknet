use argent::signer::signer_signature::{Signer, SignerSignature};
use starknet::{ContractAddress, account::Call};

#[starknet::interface]
trait IArgentMultisig<TContractState> {
    /// @notice Change threshold
    /// @dev will revert if invalid threshold
    /// @param new_threshold New threshold
    fn change_threshold(ref self: TContractState, new_threshold: usize);

    /// @notice Adds new signers to the account, additionally sets a new threshold
    /// @dev will revert when trying to add a user already in the list
    /// @dev will revert if invalid threshold
    /// @param new_threshold New threshold
    /// @param signers_to_add An array with all the signers to add
    fn add_signers(ref self: TContractState, new_threshold: usize, signers_to_add: Array<Signer>);

    /// @notice Removes account signers, additionally sets a new threshold
    /// @dev Will revert if any of the signers isn't in the multisig's list of signers
    /// @dev will revert if invalid threshold
    /// @param new_threshold New threshold
    /// @param signers_to_remove All the signers to remove
    fn remove_signers(ref self: TContractState, new_threshold: usize, signers_to_remove: Array<Signer>);

    /// @notice Replace one signer with a different one
    /// @dev Will revert when trying to remove a signer that isn't in the list
    /// @dev Will revert when trying to add a signer that is in the list or if the signer is zero
    /// @param signer_to_remove Signer to remove
    /// @param signer_to_add Signer to add
    fn replace_signer(ref self: TContractState, signer_to_remove: Signer, signer_to_add: Signer);

    /// @notice Returns the threshold
    fn get_threshold(self: @TContractState) -> usize;
    /// @notice Returns the guid of all the signers
    fn get_signer_guids(self: @TContractState) -> Array<felt252>;
    fn is_signer(self: @TContractState, signer: Signer) -> bool;
    fn is_signer_guid(self: @TContractState, signer_guid: felt252) -> bool;

    /// @notice Verifies whether a provided signature is valid and comes from one of the multisig owners.
    /// @param hash Hash of the message being signed
    /// @param signer_signature Signature to be verified
    fn is_valid_signer_signature(self: @TContractState, hash: felt252, signer_signature: SignerSignature) -> bool;
}

#[starknet::interface]
trait IArgentMultisigInternal<TContractState> {
    fn initialize(ref self: TContractState, threshold: usize, signers: Array<Signer>);
    fn assert_valid_threshold_and_signers_count(self: @TContractState, threshold: usize, signers_len: usize);
    fn assert_valid_storage(self: @TContractState);
    fn is_valid_signature_with_threshold(
        self: @TContractState, hash: felt252, threshold: u32, signer_signatures: Array<SignerSignature>
    ) -> bool;
}
