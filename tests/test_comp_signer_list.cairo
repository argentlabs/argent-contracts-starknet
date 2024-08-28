use argent::mocks::signer_list_mocks::SignerListMock;
use argent::signer_storage::interface::ISignerList;
use argent::signer_storage::signer_list::signer_list_component;
use super::MULTISIG_OWNER;

type ComponentState = signer_list_component::ComponentState<SignerListMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    signer_list_component::component_state_for_testing()
}

// Add signers

#[test]
fn test_add_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signer(MULTISIG_OWNER(1).pubkey, 0);
    assert_eq!(component.get_signers_len(), 1);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(1).pubkey);
    assert!(component.is_signer_in_list(MULTISIG_OWNER(1).pubkey));
}

#[test]
fn test_add_3_signers() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    assert_eq!(component.get_signers_len(), 3);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(1).pubkey);
    assert_eq!(*component.get_signers().at(1), MULTISIG_OWNER(2).pubkey);
    assert_eq!(*component.get_signers().at(2), MULTISIG_OWNER(3).pubkey);
}

#[test]
fn test_add_2_signers_after_one() {
    let mut component = COMPONENT_STATE();
    component.add_signer(MULTISIG_OWNER(1).pubkey, 0);
    component.add_signers(array![MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), MULTISIG_OWNER(1).pubkey);
    assert_eq!(component.get_signers_len(), 3);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(1).pubkey);
    assert_eq!(*component.get_signers().at(1), MULTISIG_OWNER(2).pubkey);
    assert_eq!(*component.get_signers().at(2), MULTISIG_OWNER(3).pubkey);
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn test_add_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    component.add_signer(MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(3).pubkey);
}

// Remove signer

#[test]
fn test_remove_first_signer() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    let last_signer = component.remove_signer(MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(3).pubkey);
    assert_eq!(last_signer, MULTISIG_OWNER(3).pubkey);
    assert_eq!(component.get_signers_len(), 2);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(2).pubkey);
    assert_eq!(*component.get_signers().at(1), MULTISIG_OWNER(3).pubkey);
}

#[test]
fn test_remove_middle_signer() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    let last_signer = component.remove_signer(MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey);
    assert_eq!(last_signer, MULTISIG_OWNER(3).pubkey);
    assert_eq!(component.get_signers_len(), 2);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(1).pubkey);
    assert_eq!(*component.get_signers().at(1), MULTISIG_OWNER(3).pubkey);
}

#[test]
fn test_remove_last_signer() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    let last_signer = component.remove_signer(MULTISIG_OWNER(3).pubkey, MULTISIG_OWNER(3).pubkey);
    assert_eq!(last_signer, MULTISIG_OWNER(2).pubkey);
    assert_eq!(component.get_signers_len(), 2);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(1).pubkey);
    assert_eq!(*component.get_signers().at(1), MULTISIG_OWNER(2).pubkey);
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_remove_unknown_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey].span(), 0);
    component.remove_signer(MULTISIG_OWNER(3).pubkey, MULTISIG_OWNER(2).pubkey);
}

#[test]
fn test_remove_all_signers() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    component
        .remove_signers(
            array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(),
            MULTISIG_OWNER(3).pubkey
        );
    assert_eq!(component.get_signers_len(), 0);
}

#[test]
fn test_remove_2_signers() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    component
        .remove_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey].span(), MULTISIG_OWNER(3).pubkey);
    assert_eq!(component.get_signers_len(), 1);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(3).pubkey);
}

// Replace signer

#[test]
fn test_replace_first_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey].span(), 0);
    component.replace_signer(MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(3).pubkey, MULTISIG_OWNER(2).pubkey);
    assert_eq!(component.get_signers_len(), 2);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(3).pubkey);
    assert_eq!(*component.get_signers().at(1), MULTISIG_OWNER(2).pubkey);
}

#[test]
fn test_replace_last_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey].span(), 0);
    component.replace_signer(MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey, MULTISIG_OWNER(2).pubkey);
    assert_eq!(component.get_signers_len(), 2);
    assert_eq!(*component.get_signers().at(0), MULTISIG_OWNER(1).pubkey);
    assert_eq!(*component.get_signers().at(1), MULTISIG_OWNER(3).pubkey);
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_replace_unknown_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1).pubkey].span(), 0);
    component.replace_signer(MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey, MULTISIG_OWNER(1).pubkey);
}

#[test]
#[should_panic(expected: ('argent/already-a-signer',))]
fn test_replace_duplicate_signer() {
    let mut component = COMPONENT_STATE();
    component.add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey].span(), 0);
    component.replace_signer(MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey);
}

// Load

#[test]
fn test_load() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    let (len, last_signer) = component.load();
    assert_eq!(len, 3);
    assert_eq!(last_signer, MULTISIG_OWNER(3).pubkey);
}

#[test]
fn test_is_signer_before() {
    let mut component = COMPONENT_STATE();
    component
        .add_signers(array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey].span(), 0);
    assert!(
        component.is_signer_before(MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(2).pubkey), "signer 1 is before signer 2"
    );
    assert!(
        component.is_signer_before(MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(3).pubkey), "signer 1 is before signer 3"
    );
    assert!(
        component.is_signer_before(MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(3).pubkey), "signer 2 is before signer 3"
    );
    assert!(
        !component.is_signer_before(MULTISIG_OWNER(2).pubkey, MULTISIG_OWNER(1).pubkey),
        "signer 2 is not before signer 1"
    );
    assert!(
        !component.is_signer_before(MULTISIG_OWNER(3).pubkey, MULTISIG_OWNER(1).pubkey),
        "signer 3 is not before signer 1"
    );
    assert!(
        !component.is_signer_before(MULTISIG_OWNER(3).pubkey, MULTISIG_OWNER(2).pubkey),
        "signer 3 is not before signer 2"
    );
}

