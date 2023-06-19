use starknet::ClassHash;

#[starknet::interface]
trait IUpgradeable<TContractState> {
    fn upgrade(
        ref self: TContractState, new_implementation: ClassHash, calldata: Array<felt252>
    ) -> Array<felt252>;
}

#[starknet::interface]
trait IUpgradeTarget<TContractState> {
    fn execute_after_upgrade(ref self: TContractState, data: Array<felt252>) -> Array<felt252>;
}

