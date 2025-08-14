use starknet::ClassHash;

#[starknet::interface]
pub trait IUpgradeable<TContractState> {
    /// @notice Upgrades the account implementation to a new class hash
    /// @dev Validates that the new implementation supports SRC5_ACCOUNT_INTERFACE_ID
    /// @dev Makes a library call to perform_upgrade on the new implementation
    /// @dev Must be called by the account itself
    /// @param new_implementation Class hash to upgrade to
    /// @param data Additional data passed to perform_upgrade, depends on the target version
    fn upgrade(ref self: TContractState, new_implementation: ClassHash, data: Array<felt252>);
}

#[starknet::interface]
pub trait IUpgradableCallbackOld<TContractState> {
    /// @notice Legacy callback for accounts upgrading from old versions
    /// @dev Used when upgrading from Argent account <0.4.0 or multisig <0.2.0
    /// @dev Can only be called by the account itself during upgrade
    /// @param data Implementation-specific upgrade data
    /// @return Arbitrary data depending on target version
    fn execute_after_upgrade(ref self: TContractState, data: Array<felt252>) -> Array<felt252>;
}

#[starknet::interface]
pub trait IUpgradableCallback<TContractState> {
    /// @notice Executes the actual upgrade to a new implementation
    /// @dev Called as a library call by the account before replacing the class hash
    /// @dev This behavior allows for extra flexibility as the upgrade logic is not defined in the old version but
    /// determined by the new implementation
    /// @dev Can only be called by the account itself during upgrade
    /// @dev Must handle class hash replacement and event emission
    /// @param new_implementation Class hash that will replace the current implementation
    /// @param data Implementation-specific upgrade data
    fn perform_upgrade(ref self: TContractState, new_implementation: ClassHash, data: Span<felt252>);
}


#[starknet::component]
pub mod upgrade_component {
    use argent::account::SRC5_ACCOUNT_INTERFACE_ID;
    use argent::introspection::{ISRC5DispatcherTrait, ISRC5LibraryDispatcher};
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

    #[generate_trait]
    pub impl UpgradableInternalImpl<TContractState, +HasComponent<TContractState>> of IUpgradeInternal<TContractState> {
        /// @notice Completes the upgrade by replacing class hash and emitting event
        /// @dev Should only be called from perform_upgrade
        fn complete_upgrade(ref self: ComponentState<TContractState>, new_implementation: ClassHash) {
            replace_class_syscall(new_implementation).expect('argent/invalid-upgrade');
            self.emit(AccountUpgraded { new_implementation });
        }
    }
}
