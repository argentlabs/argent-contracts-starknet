use argent::linked_set::linked_set::{
    LinkedSet, LinkedSetReadImpl, LinkedSetReadPrivateImpl, LinkedSetWriteImpl, LinkedSetWritePrivateImpl,
    MutableLinkedSetReadImpl,
};
use argent::mocks::linked_set_mock::linked_set_mock;
use argent::multiowner_account::signer_storage_linked_set::SignerStorageValueLinkedSetConfig;
use argent::signer::signer_signature::{SignerStorageValue, SignerTrait, SignerType, starknet_signer_from_pubkey};
use starknet::storage::{Mutable, StorageBase};

type ComponentState = linked_set_mock::ComponentState<linked_set_mock::Storage>;


fn setup_linked_set() -> StorageBase<Mutable<LinkedSet<SignerStorageValue>>> {
    let mut component: ComponentState = linked_set_mock::component_state_for_testing();
    component.linked_set
}

fn setup_three_owners() -> (StorageBase<Mutable<LinkedSet<SignerStorageValue>>>, Array<SignerStorageValue>) {
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
}

#[test]
fn test_contains() {
    let linked_set = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();

    assert(linked_set.contains(signer_storage1.hash()), 'Item1 should be in the set');
    assert(!linked_set.contains(signer_storage2.hash()), 'Item2 should not be in the set');
}

#[test]
fn test_find_last_id() {
    let linked_set = setup_linked_set();

    assert_eq!(linked_set.find_last_hash(), 0);

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    assert_eq!(linked_set.find_last_hash(), signer_storage1.hash());

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set.insert(signer_storage2);

    assert_eq!(linked_set.find_last_hash(), signer_storage2.hash());
}


#[test]
fn test_first() {
    let linked_set = setup_linked_set();

    assert!(linked_set.first().is_none(), "First item should be None for empty set");

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    let first = linked_set.first().unwrap();
    assert_eq!(first.hash(), signer_storage1.hash());
}

#[test]
fn test_next() {
    let mut linked_set = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set.insert(signer_storage2);

    let next = linked_set.next(signer_storage1.hash()).unwrap();
    assert_eq!(next.hash(), signer_storage2.hash());

    assert!(linked_set.next(signer_storage2.hash()).is_none(), "Next of last item should be None");
}

#[test]
fn test_item_id_before() {
    let linked_set = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set.insert(signer_storage2);

    assert_eq!(linked_set.item_hash_before(signer_storage2.hash()), signer_storage1.hash());
    assert_eq!(linked_set.item_hash_before(signer_storage1.hash()), 0);
}

#[test]
fn test_get_all_ids() {
    let mut linked_set = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set.insert(signer_storage2);

    let ids = linked_set.get_all_hashes();
    assert_eq!(ids.len(), 2);
    assert_eq!(*ids[0], signer_storage1.hash());
    assert_eq!(*ids[1], signer_storage2.hash());
}

#[test]
fn test_read() {
    let mut linked_set = setup_linked_set();

    let owner = starknet_signer_from_pubkey(1);
    let signer_storage = owner.storage_value();
    linked_set.insert(signer_storage);

    assert!(linked_set.contains(signer_storage.hash()), "Read set should contain added item");
}

#[test]
fn test_remove() {
    let mut linked_set = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set.insert(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set.insert(signer_storage2);

    linked_set.remove(signer_storage1.hash());

    assert!(!linked_set.contains(signer_storage1.hash()), "Removed item should not be in set");
    assert!(linked_set.contains(signer_storage2.hash()), "Non-removed item should still be in set");
}


#[test]
fn test_remove_0_1() {
    let (storage, owners) = setup_three_owners();

    storage.remove_many(array![owners[0].hash(), owners[1].hash()].span());

    let remaining_owners = storage.get_all_hashes();
    assert_eq!(remaining_owners.len(), 1);
    assert_eq!(*remaining_owners[0], owners[2].hash());
}

#[test]
fn test_remove_0_2() {
    let (storage, owners) = setup_three_owners();

    storage.remove_many(array![owners[0].hash(), owners[2].hash()].span());

    let remaining_owners = storage.get_all_hashes();
    assert_eq!(remaining_owners.len(), 1);
    assert_eq!(*remaining_owners[0], owners[1].hash());
}

#[test]
fn test_remove_1_2() {
    let (storage, owners) = setup_three_owners();

    storage.remove_many(array![owners[1].hash(), owners[2].hash()].span());

    let remaining_owners = storage.get_all_hashes();
    assert_eq!(remaining_owners.len(), 1);
    assert_eq!(*remaining_owners[0], owners[0].hash());
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
fn test_add_duplicate_item() {
    let mut linked_set = setup_linked_set();
    let owner = starknet_signer_from_pubkey(1);
    let signer_storage = owner.storage_value();
    linked_set.insert(signer_storage);
    linked_set.insert(signer_storage);
}

#[test]
#[should_panic(expected: ('linked-set/invalid-hash-to-rem',))]
fn test_remove_invalid_id() {
    let mut linked_set = setup_linked_set();

    linked_set.remove(0);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn test_remove_non_existent_item() {
    let mut linked_set = setup_linked_set();

    let owner = starknet_signer_from_pubkey(1);
    let signer_storage = owner.storage_value();
    linked_set.insert(signer_storage);

    linked_set.remove(123);
}

#[test]
#[should_panic(expected: ('linked-set/item-hash-after',))]
fn test_item_id_before_zero() {
    let mut linked_set = setup_linked_set();

    linked_set.item_hash_before(0);
}
