use argent::account::interface::{
    SRC5_ACCOUNT_INTERFACE_ID, SRC5_ACCOUNT_INTERFACE_ID_OLD_1, SRC5_ACCOUNT_INTERFACE_ID_OLD_2
};
use argent::introspection::interface::ISRC5;
use argent::introspection::interface::ISRC5Legacy;
use argent::introspection::interface::{SRC5_INTERFACE_ID, SRC5_INTERFACE_ID_OLD};
use argent::introspection::src5::src5_component;
use argent::outside_execution::interface::ERC165_OUTSIDE_EXECUTION_INTERFACE_ID;
use argent_tests::mocks::src5_mocks::SRC5Mock;

const UNSUPORTED_INTERFACE_ID: felt252 = 0xffffffff;

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
    assert(component.supports_interface(SRC5_ACCOUNT_INTERFACE_ID), 'should support account');
    assert(component.supports_interface(SRC5_ACCOUNT_INTERFACE_ID_OLD_1), 'should support account old 1');
    assert(component.supports_interface(SRC5_ACCOUNT_INTERFACE_ID_OLD_2), 'should support account old 2');
}

#[test]
fn test_introspection_src5_id() {
    let mut component = COMPONENT_STATE();
    assert(component.supports_interface(SRC5_INTERFACE_ID), 'should support src5');
    assert(component.supports_interface(SRC5_INTERFACE_ID_OLD), 'should support src5 old');
}

#[test]
fn test_introspection_outside_execution_id() {
    let mut component = COMPONENT_STATE();
    assert(component.supports_interface(ERC165_OUTSIDE_EXECUTION_INTERFACE_ID), 'should support');
}

#[test]
fn test_unsuported_interface_id() {
    let mut component = COMPONENT_STATE();
    assert(!component.supports_interface(UNSUPORTED_INTERFACE_ID), 'should not support');
}

#[test]
fn test_introspection_legacy_method() {
    let mut component = COMPONENT_STATE();
    assert(component.supportsInterface(SRC5_ACCOUNT_INTERFACE_ID) == 1, 'should support account');
    assert(component.supportsInterface(SRC5_ACCOUNT_INTERFACE_ID_OLD_1) == 1, 'should support account old 1');
    assert(component.supportsInterface(SRC5_ACCOUNT_INTERFACE_ID_OLD_2) == 1, 'should support account old 2');
    assert(component.supportsInterface(SRC5_INTERFACE_ID) == 1, 'should support src5');
    assert(component.supportsInterface(SRC5_INTERFACE_ID_OLD) == 1, 'should support src5 old');
    assert(component.supportsInterface(ERC165_OUTSIDE_EXECUTION_INTERFACE_ID) == 1, 'should support');
    assert(component.supportsInterface(UNSUPORTED_INTERFACE_ID) == 0, 'should not support');
}
