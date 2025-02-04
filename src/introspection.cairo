pub const SRC5_INTERFACE_ID: felt252 = 0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055;
pub const SRC5_INTERFACE_ID_OLD: felt252 = 0x01ffc9a7;

#[starknet::interface]
pub trait ISRC5<TContractState> {
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
}

#[starknet::interface]
pub trait ISRC5Legacy<TContractState> {
    fn supportsInterface(self: @TContractState, interfaceId: felt252) -> felt252;
}

#[starknet::component]
pub mod src5_component {
    use argent::account::{SRC5_ACCOUNT_INTERFACE_ID, SRC5_ACCOUNT_INTERFACE_ID_OLD_1, SRC5_ACCOUNT_INTERFACE_ID_OLD_2};
    use argent::introspection::{ISRC5, ISRC5Legacy, SRC5_INTERFACE_ID, SRC5_INTERFACE_ID_OLD};
    use argent::outside_execution::outside_execution::{
        ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0, ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1,
    };

    #[storage]
    pub struct Storage {}

    #[embeddable_as(SRC5Impl)]
    impl SRC5<TContractState, +HasComponent<TContractState>> of ISRC5<ComponentState<TContractState>> {
        fn supports_interface(self: @ComponentState<TContractState>, interface_id: felt252) -> bool {
            if interface_id == SRC5_INTERFACE_ID {
                true
            } else if interface_id == SRC5_ACCOUNT_INTERFACE_ID {
                true
            } else if interface_id == ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0 {
                true
            } else if interface_id == ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1 {
                true
            } else if interface_id == SRC5_INTERFACE_ID_OLD {
                true
            } else if interface_id == SRC5_ACCOUNT_INTERFACE_ID_OLD_1 {
                true
            } else if interface_id == SRC5_ACCOUNT_INTERFACE_ID_OLD_2 {
                true
            } else {
                false
            }
        }
    }

    #[embeddable_as(SRC5LegacyImpl)]
    impl SRC5Legacy<TContractState, +HasComponent<TContractState>> of ISRC5Legacy<ComponentState<TContractState>> {
        fn supportsInterface(self: @ComponentState<TContractState>, interfaceId: felt252) -> felt252 {
            if self.supports_interface(interfaceId) {
                1
            } else {
                0
            }
        }
    }
}
