use argent::account::interface::Version;
use argent::multiowner_account::recovery::Escape;
use argent::recovery::{EscapeStatus};

use argent::signer::signer_signature::{Signer, SignerSignature, starknet_signer_from_pubkey};
use argent::utils::serialization::serialize;
use crate::{ARGENT_ACCOUNT_ADDRESS, GUARDIAN, OWNER};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address_global};
use starknet::account::Call;

#[starknet::interface]
pub trait ITestArgentAccount<TContractState> {
    // IAccount
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    fn is_valid_signature(self: @TContractState, hash: felt252, signature: Array<felt252>) -> felt252;

    // External
    fn reset_owners(ref self: TContractState, new_single_owner: SignerSignature, signature_expiration: u64);
    fn reset_guardians(ref self: TContractState, new_guardian: Option<Signer>);
    fn trigger_escape_owner(ref self: TContractState, new_owner: Signer);
    fn trigger_escape_guardian(ref self: TContractState, new_guardian: Option<Signer>);
    fn escape_owner(ref self: TContractState);
    fn escape_guardian(ref self: TContractState);
    fn cancel_escape(ref self: TContractState);
    fn set_escape_security_period(ref self: TContractState, new_security_period: u64);
    // Views
    fn get_owner(self: @TContractState) -> felt252;
    fn get_guardian(self: @TContractState) -> felt252;
    fn get_owner_guid(self: @TContractState) -> felt252;
    fn get_guardian_guid(self: @TContractState) -> Option<felt252>;
    fn get_escape(self: @TContractState) -> Escape;
    fn get_version(self: @TContractState) -> Version;
    fn get_name(self: @TContractState) -> felt252;
    fn get_last_owner_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_escape_attempt(self: @TContractState) -> u64;
    fn get_escape_and_status(self: @TContractState) -> (Escape, EscapeStatus);
    fn get_escape_security_period(self: @TContractState) -> u64;

    // IErc165
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;

    // IDeprecatedArgentAccount
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn isValidSignature(self: @TContractState, hash: felt252, signatures: Array<felt252>) -> felt252;
}

pub fn initialize_account() -> ITestArgentAccountDispatcher {
    initialize_account_with(OWNER().pubkey, GUARDIAN().pubkey)
}

pub fn initialize_account_without_guardian() -> ITestArgentAccountDispatcher {
    initialize_account_with(OWNER().pubkey, 0)
}

pub fn initialize_account_with(owner: felt252, guardian: felt252) -> ITestArgentAccountDispatcher {
    let owner = starknet_signer_from_pubkey(owner);
    let guardian_signer: Option<Signer> = match guardian {
        0 => Option::None,
        _ => Option::Some(starknet_signer_from_pubkey(guardian)),
    };
    let constructor_args = (owner, guardian_signer);

    let contract = declare("ArgentAccount").expect('Failed to declare ArgentAccount').contract_class();
    let (contract_address, _) = contract
        .deploy_at(@serialize(@constructor_args), ARGENT_ACCOUNT_ADDRESS.try_into().unwrap())
        .expect('Failed to deploy ArgentAccount');

    // This will set the caller for subsequent calls (avoid 'argent/only-self')
    start_cheat_caller_address_global(contract_address);
    ITestArgentAccountDispatcher { contract_address }
}
