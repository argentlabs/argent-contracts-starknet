use lib::Version;
use account::{Escape, EscapeStatus};

#[starknet::interface]
trait IArgentAccount<TContractState> {
    // TODO Should this move into its own impl?
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: felt252,
        guardian: felt252
    ) -> felt252;
    // External
    fn change_owner(
        ref self: TContractState, new_owner: felt252, signature_r: felt252, signature_s: felt252
    );
    fn change_guardian(ref self: TContractState, new_guardian: felt252);
    fn change_guardian_backup(ref self: TContractState, new_guardian_backup: felt252);
    fn trigger_escape_owner(ref self: TContractState, new_owner: felt252);
    fn trigger_escape_guardian(ref self: TContractState, new_guardian: felt252);
    fn escape_owner(ref self: TContractState);
    fn escape_guardian(ref self: TContractState);
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
    fn get_escape_and_status(self: @TContractState) -> (Escape, EscapeStatus);
}

// TODO This could be common with the multisig 
/// Deprecated methods for compatibility reasons
#[starknet::interface]
trait IOldArgentAccount<TContractState> {
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn isValidSignature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
}
