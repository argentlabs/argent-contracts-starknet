use starknet::ClassHash;

pub trait IUpgradeInternal<TContractState> {
    fn complete_upgrade(ref self: TContractState, new_implementation: ClassHash);
}

#[starknet::component]
pub mod upgrade_component {
    use argent::account::interface::SRC5_ACCOUNT_INTERFACE_ID;
    use argent::introspection::interface::{ISRC5DispatcherTrait, ISRC5LibraryDispatcher};
    use argent::upgrade::interface::{
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
