use starknet::ClassHash;
use lib::OutsideExecution;

#[starknet::interface]
trait IAccountUpgrade<TContractState> {
    fn upgrade(
        ref self: TContractState, new_implementation: ClassHash, calldata: Array<felt252>
    ) -> Array<felt252>;
    fn execute_after_upgrade(ref self: TContractState, data: Array<felt252>) -> Array<felt252>;
}

#[starknet::interface]
trait IExecuteFromOutside<TContractState> {
    fn execute_from_outside(
        ref self: TContractState, outside_execution: OutsideExecution, signature: Array<felt252>
    ) -> Array<Span<felt252>>;

    fn get_outside_execution_message_hash(
        self: @TContractState, outside_execution: OutsideExecution
    ) -> felt252;
}

// TODO Delete as we should use SN interface
use starknet::account::Call;
trait AccountContract<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate__(ref self: TContractState, calls: Array<Call>) -> felt252;
    fn __execute__(ref self: TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
}
