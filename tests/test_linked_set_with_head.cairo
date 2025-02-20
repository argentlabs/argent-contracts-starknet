use argent::linked_set::linked_set_with_head::{
    LinkedSetWithHead, LinkedSetWithHeadReadImpl, LinkedSetWithHeadWriteImpl, MutableLinkedSetWithHeadReadImpl,
};
use argent::mocks::linked_set_mock::linked_set_mock;
use argent::multiowner_account::signer_storage_linked_set::SignerStorageValueLinkedSetConfig;
use argent::signer::signer_signature::{SignerStorageValue, SignerTrait, SignerType, starknet_signer_from_pubkey};
use starknet::storage::{Mutable, StorageBase};

type ComponentState = linked_set_mock::ComponentState<linked_set_mock::Storage>;


fn setup_linked_set() -> StorageBase<Mutable<LinkedSetWithHead<SignerStorageValue>>> {
    let mut component: ComponentState = linked_set_mock::component_state_for_testing();
    component.linked_set_with_head
}

fn setup_three_owners() -> (StorageBase<Mutable<LinkedSetWithHead<SignerStorageValue>>>, Array<SignerStorageValue>) {
    let storage = setup_linked_set();
    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    storage.insert(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    storage.insert(signer_storage2);

    let owner3 = starknet_signer_from_pubkey(3);
    let signer_storage3 = owner3.storage_value();
    storage.insert(signer_storage3);

    (storage, array![signer_storage1, signer_storage2, signer_storage3])
}

#[test]
fn test_len() {
    let linked_set = setup_linked_set();

    assert_eq!(linked_set.len(), 0);

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    assert_eq!(linked_set.len(), 1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set.insert(signer_storage2);

    assert_eq!(linked_set.len(), 2);
}

#[test]
fn test_is_empty() {
    let linked_set = setup_linked_set();

    assert(linked_set.is_empty(), 'Set should be empty initially');

    let owner = starknet_signer_from_pubkey(1);
    let signer_storage = owner.storage_value();
    linked_set.insert(signer_storage);

    assert!(!linked_set.is_empty(), "Set should not be empty after adding item");

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set.insert(signer_storage2);

    assert!(!linked_set.is_empty(), "Set should not be empty after adding two items");

    linked_set.remove(signer_storage.hash());
    assert!(!linked_set.is_empty(), "Set should not be empty after removing one of two items");

    linked_set.remove(signer_storage2.hash());
    assert!(linked_set.is_empty(), "Set should be empty after removing");
}

#[test]
fn test_contains() {
    let linked_set = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    assert(linked_set.contains(signer_storage1), 'Item1 should be in the set');
    assert(linked_set.contains_by_hash(signer_storage1.hash()), 'Item1 should be in the set');

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();

    assert(!linked_set.contains(signer_storage2), 'Item2 should not be in the set');
    assert(!linked_set.contains_by_hash(signer_storage2.hash()), 'Item2 should not be in the set');
}

#[test]
fn test_first() {
    let linked_set = setup_linked_set();

    assert!(linked_set.first().is_none(), "First item should be None for empty set");

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    let first = linked_set.first().expect('Set should have an element');
    assert_eq!(first.hash(), signer_storage1.hash());
}

#[test]
fn test_get_all_hashes() {
    let (linked_set, owners) = setup_three_owners();

    let ids = linked_set.get_all_hashes();
    assert_eq!(ids, array![owners[0].hash(), owners[1].hash(), owners[2].hash()]);
}

#[test]
fn test_remove_first_element() {
    let (mut linked_set, owners) = setup_three_owners();

    linked_set.remove(owners[0].hash());

    let remaining_owners = linked_set.get_all_hashes();
    assert_eq!(remaining_owners.len(), 2);
    assert_eq!(*remaining_owners[0], owners[1].hash());
    assert_eq!(*remaining_owners[1], owners[2].hash());
}

#[test]
fn test_remove_middle_element() {
    let (mut linked_set, owners) = setup_three_owners();

    linked_set.remove(owners[1].hash());

    let remaining_owners = linked_set.get_all_hashes();
    assert_eq!(remaining_owners.len(), 2);
    assert_eq!(*remaining_owners[0], owners[0].hash());
    assert_eq!(*remaining_owners[1], owners[2].hash());
}

#[test]
fn test_remove_last_element() {
    let (mut linked_set, owners) = setup_three_owners();

    linked_set.remove(owners[2].hash());

    let remaining_owners = linked_set.get_all_hashes();
    assert_eq!(remaining_owners.len(), 2);
    assert_eq!(*remaining_owners[0], owners[0].hash());
    assert_eq!(*remaining_owners[1], owners[1].hash());
}

#[test]
fn test_remove_only_element() {
    let mut linked_set = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    linked_set.remove(signer_storage1.hash());

    assert(linked_set.is_empty(), 'Set should be empty');
}

#[test]
#[should_panic(expected: ('linked-set/invalid-item',))]
fn test_add_invalid_item() {
    let mut linked_set = setup_linked_set();
    let invalid_signer = SignerStorageValue { stored_value: 0, signer_type: SignerType::Starknet };
    linked_set.insert(invalid_signer);
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn test_add_duplicate_first_item() {
    let (mut linked_set, owners) = setup_three_owners();
    linked_set.insert(*owners[0]);
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn test_add_duplicate_item() {
    let (mut linked_set, owners) = setup_three_owners();

    linked_set.insert(*owners[2]);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn test_remove_non_existent_item() {
    let (mut linked_set, _) = setup_three_owners();

    linked_set.remove(123);
}

#[test]
fn test_single() {
    let mut linked_set = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    let single = linked_set.single().expect('Set should have a single item');
    assert_eq!(single.hash(), signer_storage1.hash());
}

#[test]
fn test_single_empty() {
    let linked_set = setup_linked_set();

    assert!(linked_set.single().is_none(), "Set should not have a single item");
}

#[test]
fn test_single_multiple_items() {
    let (linked_set, _) = setup_three_owners();

    assert!(linked_set.single().is_none(), "Set should not have a single item");
}
