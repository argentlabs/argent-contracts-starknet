use starknet::ClassHash;

#[starknet::interface]
trait IAccountUpgrade<TContractState> {
    fn upgrade(
        ref self: TContractState, new_implementation: ClassHash, calldata: Array<felt252>
    ) -> Array<felt252>;
    fn execute_after_upgrade(ref self: TContractState, data: Array<felt252>) -> Array<felt252>;
}
