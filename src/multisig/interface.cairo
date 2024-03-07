use argent::signer::signer_signature::{Signer, SignerSignature};
use starknet::{ContractAddress, account::Call};

#[starknet::interface]
trait IArgentMultisig<TContractState> {
    /// @dev Change threshold
    /// @param new_threshold New threshold
    fn change_threshold(ref self: TContractState, new_threshold: usize);

    /// @dev Adds new signers to the account, additionally sets a new threshold
    /// @param new_threshold New threshold
    /// @param signers_to_add An array with all the signers to add
    /// @dev will revert when trying to add a user already in the list
    fn add_signers(ref self: TContractState, new_threshold: usize, signers_to_add: Array<Signer>);

    /// @dev Removes account signers, additionally sets a new threshold
    /// @param new_threshold New threshold
    /// @param signers_to_remove Should contain only current signers, otherwise it will revert
    fn remove_signers(ref self: TContractState, new_threshold: usize, signers_to_remove: Array<Signer>);

    /// @dev Re-oders the account signers
    /// @param new_signer_order Should contain only current signers, otherwise it will revert
    fn reorder_signers(ref self: TContractState, new_signer_order: Array<Signer>);

    /// @dev Replace one signer with a different one
    /// @param signer_to_remove Signer to remove
    /// @param signer_to_add Signer to add
    fn replace_signer(ref self: TContractState, signer_to_remove: Signer, signer_to_add: Signer);

    /// @dev Returns the threshold, the number of signers required to control this account
    fn get_threshold(self: @TContractState) -> usize;
    fn get_signer_guids(self: @TContractState) -> Array<felt252>;
    fn is_signer(self: @TContractState, signer: Signer) -> bool;
    fn is_signer_guid(self: @TContractState, signer_guid: felt252) -> bool;

    /// Checks if a given signature is a valid signature from one of the multisig owners
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
