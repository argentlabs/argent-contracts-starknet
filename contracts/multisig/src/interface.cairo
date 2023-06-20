use lib::Version;

#[starknet::interface]
trait IArgentMultisig<TContractState> {
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<felt252>
    ) -> felt252;
    // External
    fn change_threshold(ref self: TContractState, new_threshold: usize);
    fn add_signers(ref self: TContractState, new_threshold: usize, signers_to_add: Array<felt252>);
    fn remove_signers(
        ref self: TContractState, new_threshold: usize, signers_to_remove: Array<felt252>
    );
    fn replace_signer(ref self: TContractState, signer_to_remove: felt252, signer_to_add: felt252);
    // Views
    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
    fn get_threshold(self: @TContractState) -> usize;
    fn get_signers(self: @TContractState) -> Array<felt252>;
    fn is_signer(self: @TContractState, signer: felt252) -> bool;
    fn assert_valid_signer_signature(
        self: @TContractState,
        hash: felt252,
        signer: felt252,
        signature_r: felt252,
        signature_s: felt252
    );
    fn is_valid_signer_signature(
        self: @TContractState,
        hash: felt252,
        signer: felt252,
        signature_r: felt252,
        signature_s: felt252
    ) -> bool;
}

// TODO Should this be one itnerface in lib as the ArgentAccount uses the same?
/// Deprecated methods for compatibility reasons
#[starknet::interface]
trait IOldArgentMultisig<TContractState> {
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn isValidSignature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
}
