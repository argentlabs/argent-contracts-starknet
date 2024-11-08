use argent::account::interface::Version;
use argent::multisig_account::multisig_account::ArgentMultisigAccount;
use argent::signer::signer_signature::{Signer, SignerSignature};
use snforge_std::{declare, ContractClassTrait, ContractClass, start_cheat_caller_address_global, DeclareResultTrait};
use starknet::account::Call;
use super::super::{SIGNER_1, SIGNER_2, SIGNER_3};

#[starknet::interface]
trait ITestArgentMultisig<TContractState> {
    // IAccount
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    fn is_valid_signature(self: @TContractState, hash: felt252, signature: Array<felt252>) -> felt252;
    // IArgentMultisig
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<felt252>
    ) -> felt252;
    // External
    fn change_threshold(ref self: TContractState, new_threshold: usize);
    fn add_signers(ref self: TContractState, new_threshold: usize, signers_to_add: Array<Signer>);
    fn remove_signers(ref self: TContractState, new_threshold: usize, signers_to_remove: Array<Signer>);
    fn replace_signer(ref self: TContractState, signer_to_remove: Signer, signer_to_add: Signer);
    // Views
    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
    fn get_threshold(self: @TContractState) -> usize;
    fn get_signer_guids(self: @TContractState) -> Array<felt252>;
    fn is_signer_guid(self: @TContractState, signer: felt252) -> bool;
    fn is_signer(self: @TContractState, signer: Signer) -> bool;
    fn assert_valid_signer_signature(self: @TContractState, hash: felt252, signer_signature: SignerSignature);
    fn is_valid_signer_signature(self: @TContractState, hash: felt252, signer_signature: SignerSignature) -> bool;

    // IErc165
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;

    // IDeprecatedArgentMultisig
    fn getVersion(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn isValidSignature(self: @TContractState, hash: felt252, signatures: Array<felt252>) -> felt252;
}

fn declare_multisig() -> ContractClass {
    *declare("ArgentMultisigAccount").expect('Fail decl ArgentMultisigAccount').contract_class()
}

fn initialize_multisig() -> ITestArgentMultisigDispatcher {
    let threshold = 1;
    let signers_array = array![SIGNER_1(), SIGNER_2(), SIGNER_3(),];
    initialize_multisig_with(threshold, signers_array.span())
}

fn initialize_multisig_with_one_signer() -> ITestArgentMultisigDispatcher {
    let threshold = 1;
    let signers_array = array![SIGNER_1()];
    initialize_multisig_with(threshold, signers_array.span())
}

fn initialize_multisig_with(threshold: usize, mut signers: Span<Signer>) -> ITestArgentMultisigDispatcher {
    let class_hash = declare_multisig();
    let mut calldata = array![];
    threshold.serialize(ref calldata);
    signers.serialize(ref calldata);

    let (contract_address, _) = class_hash.deploy(@calldata).expect('Multisig deployment fail');

    // This will set the caller for subsequent calls (avoid 'argent/only-self')
    start_cheat_caller_address_global(contract_address);
    ITestArgentMultisigDispatcher { contract_address }
}
