use argent::mocks::signer_list_mocks::SignerListMock;
use argent::signer::signer_signature::{Signer, StarknetSigner, SignerTrait, starknet_signer_from_pubkey};
use argent::signer_storage::interface::ISignerList;
use argent::signer_storage::signer_list::signer_list_component;
use super::setup::constants::{MULTISIG_OWNER};

type ComponentState = signer_list_component::ComponentState<SignerListMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    signer_list_component::component_state_for_testing()
}

// Add signers

#[test]
fn test_add_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signer(MULTISIG_OWNER(1), 0);
    assert(component.get_signers_len() == 1, 'len should be 1');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(1), 'should be signer 1');
    assert(component.is_signer_in_list(MULTISIG_OWNER(1)), 'should be signer');
}

#[test]
fn test_add_3_signers() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    assert(component.get_signers_len() == 3, 'len should be 1');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(1), 'should be signer 1');
    assert(*component.get_signers().at(1) == MULTISIG_OWNER(2), 'should be signer 2');
    assert(*component.get_signers().at(2) == MULTISIG_OWNER(3), 'should be signer 3');
}

#[test]
fn test_add_2_signers_after_one() {
    let mut component = COMPONENT_STATE();
    component.add_signer(MULTISIG_OWNER(1), 0);
    component.add_signers(array![MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), MULTISIG_OWNER(1));
    assert(component.get_signers_len() == 3, 'len should be 1');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(1), 'should be signer 1');
    assert(*component.get_signers().at(1) == MULTISIG_OWNER(2), 'should be signer 2');
    assert(*component.get_signers().at(2) == MULTISIG_OWNER(3), 'should be signer 3');
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn test_add_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    component.add_signer(MULTISIG_OWNER(1), MULTISIG_OWNER(3));
}

// Remove signer

#[test]
fn test_remove_first_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    let last_signer = component.remove_signer(MULTISIG_OWNER(1), MULTISIG_OWNER(3));
    assert(last_signer == MULTISIG_OWNER(3), 'signer 3 should be last');
    assert(component.get_signers_len() == 2, 'len should be 1');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(2), 'should be signer 2');
    assert(*component.get_signers().at(1) == MULTISIG_OWNER(3), 'should be signer 3');
}

#[test]
fn test_remove_middle_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    let last_signer = component.remove_signer(MULTISIG_OWNER(2), MULTISIG_OWNER(3));
    assert(last_signer == MULTISIG_OWNER(3), 'signer 3 should be last');
    assert(component.get_signers_len() == 2, 'len should be 1');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(1), 'should be signer 1');
    assert(*component.get_signers().at(1) == MULTISIG_OWNER(3), 'should be signer 3');
}

#[test]
fn test_remove_last_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    let last_signer = component.remove_signer(MULTISIG_OWNER(3), MULTISIG_OWNER(3));
    assert(last_signer == MULTISIG_OWNER(2), 'signer 2 should be last');
    assert(component.get_signers_len() == 2, 'len should be 1');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(1), 'should be signer 1');
    assert(*component.get_signers().at(1) == MULTISIG_OWNER(2), 'should be signer 2');
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_remove_unknown_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2)].span(), 0);
    component.remove_signer(MULTISIG_OWNER(3), MULTISIG_OWNER(2));
}

#[test]
fn test_remove_all_signers() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    component.remove_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), MULTISIG_OWNER(3));
    assert(component.get_signers_len() == 0, 'len should be 0');
}

#[test]
fn test_remove_2_signers() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    component.remove_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2)].span(), MULTISIG_OWNER(3));
    assert(component.get_signers_len() == 1, 'len should be 1');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(3), 'should be signer 3');
}

// Replace signer

#[test]
fn test_replace_first_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2)].span(), 0);
    component.replace_signer(MULTISIG_OWNER(1), MULTISIG_OWNER(3), MULTISIG_OWNER(2));
    assert(component.get_signers_len() == 2, 'len should be 2');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(3), 'should be signer 3');
    assert(*component.get_signers().at(1) == MULTISIG_OWNER(2), 'should be signer 2');
}

#[test]
fn test_replace_last_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2)].span(), 0);
    component.replace_signer(MULTISIG_OWNER(2), MULTISIG_OWNER(3), MULTISIG_OWNER(2));
    assert(component.get_signers_len() == 2, 'len should be 2');
    assert(*component.get_signers().at(0) == MULTISIG_OWNER(1), 'should be signer 1');
    assert(*component.get_signers().at(1) == MULTISIG_OWNER(3), 'should be signer 3');
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_replace_unknown_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1)].span(), 0);
    component.replace_signer(MULTISIG_OWNER(2), MULTISIG_OWNER(3), MULTISIG_OWNER(1));
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn test_replace_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2)].span(), 0);
    component.replace_signer(MULTISIG_OWNER(2), MULTISIG_OWNER(1), MULTISIG_OWNER(2));
}

// Load

#[test]
fn test_load() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    let (len, last_signer) = component.load();
    assert(len == 3, 'len should be 3');
    assert(last_signer == MULTISIG_OWNER(3), 'signer 3 should be last');
}

#[test]
fn test_is_signer_before() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2), MULTISIG_OWNER(3)].span(), 0);
    assert(component.is_signer_before(MULTISIG_OWNER(1), MULTISIG_OWNER(2)), 'signer 1 is before signer 2');
    assert(component.is_signer_before(MULTISIG_OWNER(1), MULTISIG_OWNER(3)), 'signer 1 is before signer 3');
    assert(component.is_signer_before(MULTISIG_OWNER(2), MULTISIG_OWNER(3)), 'signer 2 is before signer 3');
    assert(!component.is_signer_before(MULTISIG_OWNER(2), MULTISIG_OWNER(1)), 'signer 2 is not before signer 1');
    assert(!component.is_signer_before(MULTISIG_OWNER(3), MULTISIG_OWNER(1)), 'signer 3 is not before signer 1');
    assert(!component.is_signer_before(MULTISIG_OWNER(3), MULTISIG_OWNER(2)), 'signer 3 is not before signer 2');
}

