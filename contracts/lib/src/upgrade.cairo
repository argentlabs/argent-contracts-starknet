use starknet::ClassHash;

#[starknet::interface]
trait IUpgradeable<TContractState> {
    /// @notice Upgrades the implementation of the account
    /// @dev Also call `execute_after_upgrade` on the new implementation
    /// @param implementation The class hash of the new implementation
    /// @param calldata Data to be passed to the implementation in `execute_after_upgrade`
    /// @return retdata The data returned by `execute_after_upgrade`
    fn upgrade(
        ref self: TContractState, new_implementation: ClassHash, calldata: Array<felt252>
    ) -> Array<felt252>;
}

#[starknet::interface]
trait IUpgradeTarget<TContractState> {
    /// @dev Logic to execute after an upgrade.
    /// Can only be called by the account after a call to `upgrade`.
    /// @param data Generic call data that can be passed to the method for future upgrade logic
    fn execute_after_upgrade(ref self: TContractState, data: Array<felt252>) -> Array<felt252>;
}

