use argent::account::interface::Version;
use argent::presets::argent_account::ArgentAccount;
use argent::recovery::interface::{LegacyEscape, EscapeStatus};
use argent::signer::signer_signature::{Signer, StarknetSigner, SignerSignature, starknet_signer_from_pubkey};
use snforge_std::{declare, ContractClassTrait, ContractClass, RevertedTransaction, start_prank, CheatTarget};
use starknet::{contract_address_const, account::Call};
use super::constants::{OWNER_KEY, GUARDIAN_KEY, ARGENT_ACCOUNT_ADDRESS};

#[starknet::interface]
trait ITestArgentAccount<TContractState> {
    // IAccount
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    fn is_valid_signature(self: @TContractState, hash: felt252, signature: Array<felt252>) -> felt252;

    // IArgentAccount
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: Signer,
        guardian: Option<Signer>
    ) -> felt252;
    // External
    fn change_owner(ref self: TContractState, signer_signature: SignerSignature);
    fn change_guardian(ref self: TContractState, new_guardian: Option<Signer>);
    fn change_guardian_backup(ref self: TContractState, new_guardian_backup: Option<Signer>);
    fn trigger_escape_owner(ref self: TContractState, new_owner: Signer);
    fn trigger_escape_guardian(ref self: TContractState, new_guardian: Option<Signer>);
    fn escape_owner(ref self: TContractState);
    fn escape_guardian(ref self: TContractState);
    fn cancel_escape(ref self: TContractState);
    // Views
    fn get_owner(self: @TContractState) -> felt252;
    fn get_guardian(self: @TContractState) -> felt252;
    fn get_guardian_backup(self: @TContractState) -> felt252;
    fn get_escape(self: @TContractState) -> LegacyEscape;
    fn get_version(self: @TContractState) -> Version;
    fn get_name(self: @TContractState) -> felt252;
    fn get_guardian_escape_attempts(self: @TContractState) -> u32;
    fn get_owner_escape_attempts(self: @TContractState) -> u32;
    fn get_escape_and_status(self: @TContractState) -> (LegacyEscape, EscapeStatus);

    // IErc165
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;

    // IDeprecatedArgentAccount
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn isValidSignature(self: @TContractState, hash: felt252, signatures: Array<felt252>) -> felt252;
}

fn initialize_account() -> ITestArgentAccountDispatcher {
    initialize_account_with(OWNER_KEY(), GUARDIAN_KEY())
}

fn initialize_account_without_guardian() -> ITestArgentAccountDispatcher {
    initialize_account_with(OWNER_KEY(), 0)
}

fn initialize_account_with(owner: felt252, guardian: felt252) -> ITestArgentAccountDispatcher {
    let mut calldata = array![];
    starknet_signer_from_pubkey(owner).serialize(ref calldata);
    let guardian_signer: Option<Signer> = match guardian {
        0 => { Option::None },
        _ => { Option::Some(starknet_signer_from_pubkey(guardian)) },
    };
    guardian_signer.serialize(ref calldata);

    let contract = declare("ArgentAccount");
    let contract_address = contract
        .deploy_at(@calldata, ARGENT_ACCOUNT_ADDRESS.try_into().unwrap())
        .expect('Failed to deploy ArgentAccount');

    // This will set the caller for subsequent calls (avoid 'argent/only-self')
    start_prank(CheatTarget::One(contract_address), contract_address);
    ITestArgentAccountDispatcher { contract_address }
}
