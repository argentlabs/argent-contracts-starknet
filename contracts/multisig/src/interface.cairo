use lib::Version;

#[starknet::interface]
trait IArgentMultisig<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    /// Self deployment meaning that the multisig pays for it's own deployment fee.
    /// In this scenario the multisig only requires the signature from one of the owners.
    /// This allows for better UX. UI must make clear that the funds are not safe from a bad signer until the deployment happens.
    /// @dev Validates signature for self deployment.
    /// @dev If signers can't be trusted, it's recommended to start with a 1:1 multisig and add other signers late
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<felt252>
    ) -> felt252;

    /// @dev Change threshold
    /// @param new_threshold New threshold
    fn change_threshold(ref self: TContractState, new_threshold: usize);

    /// @dev Adds new signers to the account, additionally sets a new threshold
    /// @param new_threshold New threshold
    /// @param signers_to_add An array with all the signers to add
    /// @dev will revert when trying to add a user already in the list
    fn add_signers(ref self: TContractState, new_threshold: usize, signers_to_add: Array<felt252>);

    /// @dev Removes account signers, additionally sets a new threshold
    /// @param new_threshold New threshold
    /// @param signers_to_remove Should contain only current signers, otherwise it will revert
    fn remove_signers(
        ref self: TContractState, new_threshold: usize, signers_to_remove: Array<felt252>
    );

    /// @dev Replace one signer with a different one
    /// @param signer_to_remove Signer to remove
    /// @param signer_to_add Signer to add
    fn replace_signer(ref self: TContractState, signer_to_remove: felt252, signer_to_add: felt252);

    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;

    /// @dev Returns the threshold, the number of signers required to control this account
    fn get_threshold(self: @TContractState) -> usize;
    fn get_signers(self: @TContractState) -> Array<felt252>;
    fn is_signer(self: @TContractState, signer: felt252) -> bool;

    /// Checks if a given signature is a valid signature from one of the multisig owners
    fn is_valid_signer_signature(
        self: @TContractState,
        hash: felt252,
        signer: felt252,
        signature_r: felt252,
        signature_s: felt252
    ) -> bool;
}

/// Deprecated methods for compatibility reasons
#[starknet::interface]
trait IDeprecatedArgentMultisig<TContractState> {
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    /// For compatibility reasons this method returns 1 when the signature is valid, and panics otherwise
    fn isValidSignature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
}
