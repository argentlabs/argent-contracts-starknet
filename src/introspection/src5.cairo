#[starknet::component]
mod src5_component {
    use argent::account::interface::{
        SRC5_ACCOUNT_INTERFACE_ID, SRC5_ACCOUNT_INTERFACE_ID_OLD_1, SRC5_ACCOUNT_INTERFACE_ID_OLD_2
    };
    use argent::introspection::interface::{ISRC5, ISRC5Legacy};
    use argent::introspection::interface::{SRC5_INTERFACE_ID, SRC5_INTERFACE_ID_OLD};
    use argent::outside_execution::interface::ERC165_OUTSIDE_EXECUTION_INTERFACE_ID;

    #[storage]
    struct Storage {}

    #[embeddable_as(SRC5Impl)]
    impl SRC5<TContractState, +HasComponent<TContractState>> of ISRC5<ComponentState<TContractState>> {
        fn supports_interface(self: @ComponentState<TContractState>, interface_id: felt252) -> bool {
            if interface_id == SRC5_INTERFACE_ID {
                true
            } else if interface_id == SRC5_ACCOUNT_INTERFACE_ID {
                true
            } else if interface_id == ERC165_OUTSIDE_EXECUTION_INTERFACE_ID {
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
        fn supportsInterface(self: @ComponentState<TContractState>, interfaceId: felt252) -> bool {
            self.supports_interface(interfaceId)
        }
    }
}
