use argent::signer::interface::ISignerList;
use argent::signer::{signer_signature::{Signer, StarknetSigner, IntoGuid}, signer_list::signer_list_component,};
use argent_tests::mocks::signer_list_mocks::SignerListMock;
use core::array::ArrayTrait;

const signer_pubkey_1: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_pubkey_2: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const signer_pubkey_3: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;

type ComponentState = signer_list_component::ComponentState<SignerListMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    signer_list_component::component_state_for_testing()
}

// Add signers

#[test]
fn test_add_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signer(signer_pubkey_1, 0);
    assert(component.get_signers_len() == 1, 'len should be 1');
    assert(*component.get_signers().at(0) == signer_pubkey_1, 'should be signer 1');
    assert(component.is_signer_in_list(signer_pubkey_1), 'should be signer');
}

#[test]
fn test_add_3_signers() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    assert(component.get_signers_len() == 3, 'len should be 1');
    assert(*component.get_signers().at(0) == signer_pubkey_1, 'should be signer 1');
    assert(*component.get_signers().at(1) == signer_pubkey_2, 'should be signer 2');
    assert(*component.get_signers().at(2) == signer_pubkey_3, 'should be signer 3');
}

#[test]
fn test_add_2_signers_after_one() {
    let mut component = COMPONENT_STATE();
    component.add_signer(signer_pubkey_1, 0);
    component.add_signers(array![signer_pubkey_2, signer_pubkey_3].span(), signer_pubkey_1);
    assert(component.get_signers_len() == 3, 'len should be 1');
    assert(*component.get_signers().at(0) == signer_pubkey_1, 'should be signer 1');
    assert(*component.get_signers().at(1) == signer_pubkey_2, 'should be signer 2');
    assert(*component.get_signers().at(2) == signer_pubkey_3, 'should be signer 3');
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn test_add_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    component.add_signer(signer_pubkey_1, signer_pubkey_3);
}

// Remove signer

#[test]
fn test_remove_first_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    let last_signer = component.remove_signer(signer_pubkey_1, signer_pubkey_3);
    assert(last_signer == signer_pubkey_3, 'signer 3 should be last');
    assert(component.get_signers_len() == 2, 'len should be 1');
    assert(*component.get_signers().at(0) == signer_pubkey_2, 'should be signer 2');
    assert(*component.get_signers().at(1) == signer_pubkey_3, 'should be signer 3');
}

#[test]
fn test_remove_middle_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    let last_signer = component.remove_signer(signer_pubkey_2, signer_pubkey_3);
    assert(last_signer == signer_pubkey_3, 'signer 3 should be last');
    assert(component.get_signers_len() == 2, 'len should be 1');
    assert(*component.get_signers().at(0) == signer_pubkey_1, 'should be signer 1');
    assert(*component.get_signers().at(1) == signer_pubkey_3, 'should be signer 3');
}

#[test]
fn test_remove_last_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    let last_signer = component.remove_signer(signer_pubkey_3, signer_pubkey_3);
    assert(last_signer == signer_pubkey_2, 'signer 2 should be last');
    assert(component.get_signers_len() == 2, 'len should be 1');
    assert(*component.get_signers().at(0) == signer_pubkey_1, 'should be signer 1');
    assert(*component.get_signers().at(1) == signer_pubkey_2, 'should be signer 2');
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_remove_unknown_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2].span(), 0);
    component.remove_signer(signer_pubkey_3, signer_pubkey_2);
}

#[test]
fn test_remove_all_signers() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    component.remove_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), signer_pubkey_3);
    assert(component.get_signers_len() == 0, 'len should be 0');
}

#[test]
fn test_remove_2_signers() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    component.remove_signers(array![signer_pubkey_1, signer_pubkey_2].span(), signer_pubkey_3);
    assert(component.get_signers_len() == 1, 'len should be 1');
    assert(*component.get_signers().at(0) == signer_pubkey_3, 'should be signer 3');
}

// Replace signer

#[test]
fn test_replace_first_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2].span(), 0);
    component.replace_signer(signer_pubkey_1, signer_pubkey_3, signer_pubkey_2);
    assert(component.get_signers_len() == 2, 'len should be 2');
    assert(*component.get_signers().at(0) == signer_pubkey_3, 'should be signer 3');
    assert(*component.get_signers().at(1) == signer_pubkey_2, 'should be signer 2');
}

#[test]
fn test_replace_last_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2].span(), 0);
    component.replace_signer(signer_pubkey_2, signer_pubkey_3, signer_pubkey_2);
    assert(component.get_signers_len() == 2, 'len should be 2');
    assert(*component.get_signers().at(0) == signer_pubkey_1, 'should be signer 1');
    assert(*component.get_signers().at(1) == signer_pubkey_3, 'should be signer 3');
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_replace_unknown_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1].span(), 0);
    component.replace_signer(signer_pubkey_2, signer_pubkey_3, signer_pubkey_1);
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn test_replace_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2].span(), 0);
    component.replace_signer(signer_pubkey_2, signer_pubkey_1, signer_pubkey_2);
}

// Load

#[test]
fn test_load() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    let (len, last_signer) = component.load();
    assert(len == 3, 'len shoudl be 3');
    assert(last_signer == signer_pubkey_3, 'signer 3 should be last');
}

#[test]
fn test_is_signer_before() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![signer_pubkey_1, signer_pubkey_2, signer_pubkey_3].span(), 0);
    assert(component.is_signer_before(signer_pubkey_1, signer_pubkey_2), 'signer 1 is before signer 2');
    assert(component.is_signer_before(signer_pubkey_1, signer_pubkey_3), 'signer 1 is before signer 3');
    assert(component.is_signer_before(signer_pubkey_2, signer_pubkey_3), 'signer 2 is before signer 3');
    assert(!component.is_signer_before(signer_pubkey_2, signer_pubkey_1), 'signer 2 is not before signer 1');
    assert(!component.is_signer_before(signer_pubkey_3, signer_pubkey_1), 'signer 3 is not before signer 1');
    assert(!component.is_signer_before(signer_pubkey_3, signer_pubkey_2), 'signer 3 is not before signer 2');
}
