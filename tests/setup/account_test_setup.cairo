use argent::account::interface::Version;
use argent::presets::argent_account::ArgentAccount;
use argent::recovery::interface::{EscapeStatus, LegacyEscape};
use argent::signer::signer_signature::{Signer, SignerSignature, StarknetSigner, starknet_signer_from_pubkey};
use core::traits::TryInto;
use snforge_std::{CheatSpan, ContractClass, ContractClassTrait, DeclareResult, cheat_caller_address, declare};
use starknet::ContractAddress;
use starknet::account::Call;
use super::constants::{ARGENT_ACCOUNT_ADDRESS, GUARDIAN, OWNER};

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
        guardian: Option<Signer>,
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
    fn set_escape_security_period(ref self: TContractState, new_security_period: u64);
    // Views
    fn get_owner(self: @TContractState) -> felt252;
    fn get_guardian(self: @TContractState) -> felt252;
    fn get_guardian_backup(self: @TContractState) -> felt252;
    fn get_owner_guid(self: @TContractState) -> felt252;
    fn get_guardian_guid(self: @TContractState) -> Option<felt252>;
    fn get_guardian_backup_guid(self: @TContractState) -> Option<felt252>;
    fn get_escape(self: @TContractState) -> LegacyEscape;
    fn get_version(self: @TContractState) -> Version;
    fn get_name(self: @TContractState) -> felt252;
    fn get_last_owner_escape_attempt(self: @TContractState) -> u64;
    fn get_last_guardian_escape_attempt(self: @TContractState) -> u64;
    fn get_escape_and_status(self: @TContractState) -> (LegacyEscape, EscapeStatus);
    fn get_escape_security_period(self: @TContractState) -> u64;

    // IErc165
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;

    // IDeprecatedArgentAccount
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn isValidSignature(self: @TContractState, hash: felt252, signatures: Array<felt252>) -> felt252;
}

fn initialize_account() -> ITestArgentAccountDispatcher {
    initialize_account_with(OWNER().pubkey, GUARDIAN().pubkey)
}

fn initialize_account_without_guardian() -> ITestArgentAccountDispatcher {
    initialize_account_with(OWNER().pubkey, 0)
}

fn initialize_account_with(owner: felt252, guardian: felt252) -> ITestArgentAccountDispatcher {
    let mut calldata = array![];
    starknet_signer_from_pubkey(owner).serialize(ref calldata);
    let guardian_signer: Option<Signer> = match guardian {
        0 => Option::None,
        _ => Option::Some(starknet_signer_from_pubkey(guardian)),
    };
    guardian_signer.serialize(ref calldata);

    let declare_result = declare("ArgentAccount");
    let contract_class = match declare_result {
        Result::Ok(declare_result) => match declare_result {
            DeclareResult::Success(contract_class) => contract_class,
            DeclareResult::AlreadyDeclared(contract_class) => contract_class,
        },
        Result::Err(_) => panic_with_felt252('err declaring ArgentAccount'),
    };

    let (contract_address, _) = contract_class
        .deploy_at(@calldata, ARGENT_ACCOUNT_ADDRESS.try_into().unwrap())
        .expect('Failed to deploy ArgentAccount');

    // This will set the caller for subsequent calls (avoid 'argent/only-self')
    cheat_caller_address(contract_address, contract_address, CheatSpan::Indefinite(()));
    ITestArgentAccountDispatcher { contract_address }
}
