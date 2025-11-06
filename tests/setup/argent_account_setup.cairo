use argent::account::Version;
use argent::multiowner_account::owner_alive::OwnerAliveSignature;
use argent::multiowner_account::recovery::Escape;
use argent::recovery::{EscapeStatus};
use argent::signer::signer_signature::{Signer, SignerInfo, SignerType};
use argent::utils::serialization::serialize;
use crate::{SignerKeyPair, SignerKeyPairImpl, StarknetKeyPair};
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
    fn change_owners(
        ref self: TContractState,
        owner_guids_to_remove: Array<felt252>,
        owners_to_add: Array<Signer>,
        owner_alive_signature: Option<OwnerAliveSignature>,
    );
    fn change_guardians(
        ref self: TContractState, guardian_guids_to_remove: Array<felt252>, guardians_to_add: Array<Signer>,
    );
    fn trigger_escape_owner(ref self: TContractState, new_owner: Signer);
    fn trigger_escape_guardian(ref self: TContractState, new_guardian: Option<Signer>);
    fn escape_owner(ref self: TContractState);
    fn escape_guardian(ref self: TContractState);
    fn cancel_escape(ref self: TContractState);
    fn set_escape_security_period(ref self: TContractState, new_security_period: u64);
    // Views
    fn get_owner(self: @TContractState) -> felt252;
    fn get_owner_type(self: @TContractState) -> SignerType;
    fn get_owner_guid(self: @TContractState) -> felt252;
    fn get_guardian(self: @TContractState) -> felt252;
    fn get_guardian_type(self: @TContractState) -> Option<SignerType>;
    fn get_owners_info(self: @TContractState) -> Array<SignerInfo>;
    fn get_guardian_guid(self: @TContractState) -> Option<felt252>;
    fn get_guardians_info(self: @TContractState) -> Array<SignerInfo>;
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

    // Session
    fn revoke_session(ref self: TContractState, session_hash: felt252);
    fn revoke_sessions(ref self: TContractState, session_hashes: Array<felt252>);
    fn is_session_revoked(self: @TContractState, session_hash: felt252) -> bool;
}

pub struct ArgentAccountSetup {
    pub owners: Array<SignerKeyPair>,
    pub guardians: Array<SignerKeyPair>,
    pub account: ITestArgentAccountDispatcher,
}

#[derive(Drop)]
pub struct ArgentAccountWithoutGuardianSetup {
    pub owners: Array<SignerKeyPair>,
    pub account: ITestArgentAccountDispatcher,
}

// This initializes an ArgentAccount with an owner and a guardian on the Stark curve
pub fn initialize_account() -> ArgentAccountSetup {
    let owners = array![SignerKeyPair::Starknet(StarknetKeyPair::random())];
    let guardians = array![SignerKeyPair::Starknet(StarknetKeyPair::random())];
    let account = initialize_account_with(owners.span(), guardians.span());
    ArgentAccountSetup { owners, guardians, account }
}

// This initializes an ArgentAccount with an owner on the Stark curve
pub fn initialize_account_without_guardian() -> ArgentAccountWithoutGuardianSetup {
    let owners = array![SignerKeyPair::Starknet(StarknetKeyPair::random())];
    let account = initialize_account_with(owners.span(), array![].span());
    ArgentAccountWithoutGuardianSetup { owners, account }
}


// This initializes an ArgentAccount with owner_count owners and guardian_count guardians on the Stark surve
pub fn initialize_account_with_owners_and_guardians(owner_count: usize, guardian_count: usize) -> ArgentAccountSetup {
    assert!(owner_count > 0, "owner_count must be greater than 0");
    assert!(guardian_count > 0, "guardian_count must be greater than 0");
    let mut owners = array![];
    let mut guardians = array![];
    for _ in 0..owner_count {
        owners.append(SignerKeyPair::Starknet(StarknetKeyPair::random()));
    };
    for _ in 0..guardian_count {
        guardians.append(SignerKeyPair::Starknet(StarknetKeyPair::random()));
    };
    let account = initialize_account_with(owners.span(), guardians.span());
    ArgentAccountSetup { owners, guardians, account }
}


// This could return a ArgentAccountWithoutGuardianSetup. But that would be less flexible.
fn initialize_account_with(
    owners: Span<SignerKeyPair>, guardians: Span<SignerKeyPair>,
) -> ITestArgentAccountDispatcher {
    let guardian = if guardians.len() > 0 {
        Option::Some(guardians[0].signer())
    } else {
        Option::None
    };
    let owner = owners[0].signer();
    let constructor_args = (owner, guardian);

    let contract = declare("ArgentAccount").expect('Failed to declare ArgentAccount').contract_class();
    let (contract_address, _) = contract.deploy(@serialize(@constructor_args)).expect('Failed to deploy ArgentAccount');

    // This will set the caller for subsequent calls (avoid 'argent/only-self')
    start_cheat_caller_address_global(contract_address);
    let account = ITestArgentAccountDispatcher { contract_address };

    let mut guardians_to_add = array![];
    for i in 1..guardians.len() {
        guardians_to_add.append(guardians[i].signer());
    };
    account.change_guardians(guardian_guids_to_remove: array![], :guardians_to_add);

    let mut owners_to_add = array![];
    for i in 1..owners.len() {
        owners_to_add.append(owners[i].signer());
    };
    account.change_owners(owner_guids_to_remove: array![], :owners_to_add, owner_alive_signature: Option::None);
    account
}
