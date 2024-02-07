use argent::common::version::Version;
use argent::signer::signer_signature::{Signer, SignerSignature};
use starknet::account::Call;

const SRC5_ACCOUNT_INTERFACE_ID: felt252 = 0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd;
const SRC5_ACCOUNT_INTERFACE_ID_OLD_1: felt252 = 0xa66bd575;
const SRC5_ACCOUNT_INTERFACE_ID_OLD_2: felt252 = 0x3943f10f;

#[starknet::interface]
trait IArgentAccount<TContractState> {
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<Signer>
    ) -> felt252;
    fn is_valid_signature(self: @TContractState, hash: felt252, signature: Array<felt252>) -> felt252;
    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
}
