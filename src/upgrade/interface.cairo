use argent::account::interface::Version;
use starknet::ClassHash;
#[starknet::interface]
trait IUpgradeable<TContractState> {
    /// @notice Upgrades the implementation of the account by doing a library call to `perform_upgrade` on the new implementation
    /// @param new_implementation The class hash of the new implementation
    /// @param data Data to be passed in `perform_upgrade` in the `data` argument
    fn upgrade(ref self: TContractState, new_implementation: ClassHash, data: Array<felt252>);
}

#[starknet::interface]
trait IUpgradableCallbackOld<TContractState> {
    /// Called after upgrading when coming from old accounts (argent account < 0.4.0 and multisig < 0.2.0)
    /// @dev Logic to execute after an upgrade
    /// Can only be called by the account after a call to `upgrade`
    /// @param data Generic call data that can be passed to the function for future upgrade logic
    fn execute_after_upgrade(ref self: TContractState, data: Array<felt252>) -> Array<felt252>;
}

#[starknet::interface]
trait IUpgradableCallback<TContractState> {
    /// Called to upgrade to given implementation
    /// This function is responsible for performing the actual class replacement and emitting the events
    /// The methods can only be called by the account after a call to `upgrade`
    /// @param new_implementation The class hash of the new implementation
    fn perform_upgrade(ref self: TContractState, new_implementation: ClassHash, data: Span<felt252>);
}
