use argent::account::interface::{
    SRC5_ACCOUNT_INTERFACE_ID, SRC5_ACCOUNT_INTERFACE_ID_OLD_1, SRC5_ACCOUNT_INTERFACE_ID_OLD_2
};
use argent::introspection::interface::{SRC5_INTERFACE_ID, ISRC5, ISRC5Legacy, SRC5_INTERFACE_ID_OLD};
use argent::introspection::src5::src5_component;
use argent::mocks::src5_mocks::SRC5Mock;
use argent::outside_execution::interface::{
    ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0, ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1
};

const UNSUPPORTED_INTERFACE_ID: felt252 = 0xffffffff;

type ComponentState = src5_component::ComponentState<SRC5Mock::ContractState>;

fn CONTRACT_STATE() -> SRC5Mock::ContractState {
    SRC5Mock::contract_state_for_testing()
}

fn COMPONENT_STATE() -> ComponentState {
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

