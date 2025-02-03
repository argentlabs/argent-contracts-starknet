use starknet::ClassHash;

#[starknet::interface]
pub trait IUpgradeable<TContractState> {
    /// @notice Upgrades the implementation of the account by doing a library call to `perform_upgrade` on the new
    /// implementation @param new_implementation The class hash of the new implementation
    /// @param data Data to be passed in `perform_upgrade` in the `data` argument
    fn upgrade(ref self: TContractState, new_implementation: ClassHash, data: Array<felt252>);
}

#[starknet::interface]
pub trait IUpgradableCallbackOld<TContractState> {
    /// Called after upgrading when coming from old accounts (argent account < 0.4.0 and multisig < 0.2.0)
    /// @dev Logic to execute after an upgrade
    /// Can only be called by the account after a call to `upgrade`
    /// @param data Generic call data that can be passed to the function for future upgrade logic
    fn execute_after_upgrade(ref self: TContractState, data: Array<felt252>) -> Array<felt252>;
}

#[starknet::interface]
pub trait IUpgradableCallback<TContractState> {
    /// Called to upgrade to given implementation
    /// This function is responsible for performing the actual class replacement and emitting the events
    /// The methods can only be called by the account after a call to `upgrade`
    /// @param new_implementation The class hash of the new implementation
    fn perform_upgrade(ref self: TContractState, new_implementation: ClassHash, data: Span<felt252>);
}

pub trait IUpgradeInternal<TContractState> {
    fn complete_upgrade(ref self: TContractState, new_implementation: ClassHash);
}

#[starknet::component]
pub mod upgrade_component {
    use argent::account::SRC5_ACCOUNT_INTERFACE_ID;
    use argent::introspection::interface::{ISRC5DispatcherTrait, ISRC5LibraryDispatcher};
    use argent::upgrade::{
        IUpgradableCallback, IUpgradableCallbackDispatcherTrait, IUpgradableCallbackLibraryDispatcher, IUpgradeable,
    };
    use argent::utils::asserts::assert_only_self;
    use starknet::{ClassHash, syscalls::replace_class_syscall};

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        AccountUpgraded: AccountUpgraded,
    }

    /// @notice Emitted when the implementation of the account changes
    /// @param new_implementation The new implementation
    #[derive(Drop, starknet::Event)]
    struct AccountUpgraded {
        new_implementation: ClassHash,
    }

    #[embeddable_as(UpgradableImpl)]
    impl Upgradable<
        TContractState, +HasComponent<TContractState>, +IUpgradableCallback<TContractState>,
    > of IUpgradeable<ComponentState<TContractState>> {
        fn upgrade(ref self: ComponentState<TContractState>, new_implementation: ClassHash, data: Array<felt252>) {
            assert_only_self();
            let supports_interface = ISRC5LibraryDispatcher { class_hash: new_implementation }
                .supports_interface(SRC5_ACCOUNT_INTERFACE_ID);
            assert(supports_interface, 'argent/invalid-implementation');
            IUpgradableCallbackLibraryDispatcher { class_hash: new_implementation }
                .perform_upgrade(new_implementation, data.span());
        }
    }

    pub impl UpgradableInternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of super::IUpgradeInternal<ComponentState<TContractState>> {
        fn complete_upgrade(ref self: ComponentState<TContractState>, new_implementation: ClassHash) {
            replace_class_syscall(new_implementation).expect('argent/invalid-upgrade');
            self.emit(AccountUpgraded { new_implementation });
        }
    }
}
