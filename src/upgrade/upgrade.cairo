use argent::account::interface::SRC5_ACCOUNT_INTERFACE_ID;

use starknet::{ClassHash, syscalls::replace_class_syscall};


#[starknet::interface]
trait IUpgradeInternal<TContractState> {
    fn complete_upgrade(ref self: TContractState, new_implementation: ClassHash);
}


#[starknet::component]
mod upgrade_component {
    use argent::account::interface::SRC5_ACCOUNT_INTERFACE_ID;
    use argent::introspection::interface::{ISRC5LibraryDispatcher, ISRC5DispatcherTrait};
    use argent::upgrade::interface::{
        IUpgradableCallback, IUpgradeable, IUpgradableCallbackLibraryDispatcher, IUpgradableCallbackDispatcherTrait
    };
    use argent::utils::asserts::assert_only_self;
    use starknet::{ClassHash, syscalls::replace_class_syscall};

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccountUpgraded: AccountUpgraded,
    }

    /// @notice Emitted when the implementation of the account changes
    /// @param new_implementation The new implementation
    #[derive(Drop, starknet::Event)]
    struct AccountUpgraded {
        new_implementation: ClassHash
    }

    #[embeddable_as(UpgradableImpl)]
    impl Upgradable<
        TContractState, +HasComponent<TContractState>, +IUpgradableCallback<TContractState>
    > of IUpgradeable<ComponentState<TContractState>> {
        fn upgrade(
            ref self: ComponentState<TContractState>, new_implementation: ClassHash, calldata: Array<felt252>
        ) -> Array<felt252> {
            assert_only_self();

            let supports_interface = ISRC5LibraryDispatcher { class_hash: new_implementation }
                .supports_interface(SRC5_ACCOUNT_INTERFACE_ID);
            assert(supports_interface, 'argent/invalid-implementation');
            IUpgradableCallbackLibraryDispatcher { class_hash: new_implementation }
                .perform_upgrade(new_implementation, calldata.span());
            array![]
        }
    }

    #[embeddable_as(UpgradableInternalImpl)]
    impl UpgradableInternal<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of super::IUpgradeInternal<ComponentState<TContractState>> {
        fn complete_upgrade(ref self: ComponentState<TContractState>, new_implementation: ClassHash) {
            replace_class_syscall(new_implementation).expect('argent/invalid-upgrade');
            self.emit(AccountUpgraded { new_implementation });
        }
    }
}
