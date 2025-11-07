use argent::account::{SRC5_ACCOUNT_INTERFACE_ID, SRC5_ACCOUNT_INTERFACE_ID_OLD_1, SRC5_ACCOUNT_INTERFACE_ID_OLD_2};
use argent::introspection::{ISRC5, ISRC5Legacy, SRC5_INTERFACE_ID, SRC5_INTERFACE_ID_OLD, src5_component};
use argent::outside_execution::outside_execution::{
    ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0, ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1,
};

const UNSUPPORTED_INTERFACE_ID: felt252 = 0xffffffff;

#[starknet::contract]
pub mod SRC5Mock {
    use argent::introspection::src5_component;

    component!(path: src5_component, storage: src5, event: SRC5Events);
    #[abi(embed_v0)]
    impl SRC5 = src5_component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Legacy = src5_component::SRC5LegacyImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: src5_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SRC5Events: src5_component::Event,
    }
}

fn COMPONENT_STATE() -> src5_component::ComponentState<SRC5Mock::ContractState> {
    src5_component::component_state_for_testing()
}

#[test]
fn test_introspection_account_id() {
    let mut component = COMPONENT_STATE();
    assert!(component.supports_interface(SRC5_ACCOUNT_INTERFACE_ID));
    assert!(component.supports_interface(SRC5_ACCOUNT_INTERFACE_ID_OLD_1));
    assert!(component.supports_interface(SRC5_ACCOUNT_INTERFACE_ID_OLD_2));
}

#[test]
fn test_introspection_src5_id() {
    let mut component = COMPONENT_STATE();
    assert!(component.supports_interface(SRC5_INTERFACE_ID));
    assert!(component.supports_interface(SRC5_INTERFACE_ID_OLD));
}

#[test]
fn test_introspection_outside_execution_id() {
    let mut component = COMPONENT_STATE();
    assert!(component.supports_interface(ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0));
    assert!(component.supports_interface(ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1));
}

#[test]
fn test_unsupported_interface_id() {
    let mut component = COMPONENT_STATE();
    assert!(!component.supports_interface(UNSUPPORTED_INTERFACE_ID));
}

#[test]
fn test_introspection_legacy_method() {
    let mut component = COMPONENT_STATE();
    assert_eq!(component.supportsInterface(SRC5_ACCOUNT_INTERFACE_ID), 1);
    assert_eq!(component.supportsInterface(SRC5_ACCOUNT_INTERFACE_ID_OLD_1), 1);
    assert_eq!(component.supportsInterface(SRC5_ACCOUNT_INTERFACE_ID_OLD_2), 1);
    assert_eq!(component.supportsInterface(SRC5_INTERFACE_ID), 1);
    assert_eq!(component.supportsInterface(SRC5_INTERFACE_ID_OLD), 1);
    assert_eq!(component.supportsInterface(ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0), 1);
    assert_eq!(component.supportsInterface(ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1), 1);
    assert_eq!(component.supportsInterface(UNSUPPORTED_INTERFACE_ID), 0);
}

