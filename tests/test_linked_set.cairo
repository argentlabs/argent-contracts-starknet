use argent::mocks::multiowner_mock::MultiownerMock;
use argent::multiowner_account::argent_account::ArgentAccount;
use argent::multiowner_account::owner_manager::{
    SignerStorageValueSetItem, owner_manager_component, owner_manager_component::PrivateTrait, IOwnerManager,
    IOwnerManagerInternal
};
use argent::signer::signer_signature::{
    SignerTrait, SignerStorageValue, SignerSignatureTrait, SignerSpanTrait, Signer, SignerSignature,
    starknet_signer_from_pubkey, SignerType
};
use argent::utils::linked_set::{LinkedSetMut, LinkedSetTraitMut, LinkedSetMutImpl, LinkedSet, LinkedSetTrait};

type ComponentState = owner_manager_component::ComponentState<MultiownerMock::ContractState>;

fn setup_linked_set() -> (LinkedSetMut<SignerStorageValue>, LinkedSet<SignerStorageValue>) {
    let mut component: ComponentState = owner_manager_component::component_state_for_testing();
    let linked_set_mut = component.owners_storage_mut();
    let linked_set: LinkedSet<SignerStorageValue> = component.owners_storage();
    (linked_set_mut, linked_set)
}

fn setup_three_owners() -> (ComponentState, Array<SignerStorageValue>) {
    let mut component = owner_manager_component::component_state_for_testing();
    let mut linked_set_mut = component.owners_storage_mut();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set_mut.add_item(signer_storage2);

    let owner3 = starknet_signer_from_pubkey(3);
    let signer_storage3 = owner3.storage_value();
    linked_set_mut.add_item(signer_storage3);

    (component, array![signer_storage1, signer_storage2, signer_storage3])
}
#[test]
fn test_len() {
    let (linked_set_mut, linked_set) = setup_linked_set();
    assert_eq!(linked_set.len(), 0);

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    assert_eq!(linked_set.len(), 1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set_mut.add_item(signer_storage2);

    assert_eq!(linked_set.len(), 2);
}

#[test]
fn test_is_empty() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    assert(linked_set.is_empty(), 'Set should be empty initially');

    let owner = starknet_signer_from_pubkey(1);
    let signer_storage = owner.storage_value();
    linked_set_mut.add_item(signer_storage);

    assert!(!linked_set.is_empty(), "Set should not be empty after adding item");
}

#[test]
fn test_is_in() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();

    assert(linked_set.is_in(signer_storage1), 'Item1 should be in the set');
    assert(!linked_set.is_in(signer_storage2), 'Item2 should not be in the set');
}

#[test]
fn test_is_in_id() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    assert(linked_set.is_in_id(signer_storage1.id()), 'ID1 should be in the set');
    assert!(!linked_set.is_in_id(123), "Random ID should not be in the set");
}

#[test]
fn test_find_last_id() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    assert_eq!(linked_set.find_last_id(), 0);

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    assert_eq!(linked_set.find_last_id(), signer_storage1.id());

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set_mut.add_item(signer_storage2);

    assert_eq!(linked_set.find_last_id(), signer_storage2.id());
}


#[test]
fn test_first() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    assert!(linked_set.first().is_none(), "First item should be None for empty set");

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    let first = linked_set.first().unwrap();
    assert_eq!(first.id(), signer_storage1.id());
}

#[test]
fn test_single() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    assert!(linked_set.single().is_none(), "Single item should be None for empty set");

    let owner1 = starknet_signer_from_pubkey(1);
    linked_set_mut.add_item(owner1.storage_value());
    let single = linked_set.single().unwrap();
    assert_eq!(single.id(), owner1.storage_value().id());
    
    linked_set_mut.add_item(starknet_signer_from_pubkey(2).storage_value());
    assert!(linked_set.single().is_none(), "Single item should be None if there are multiple elements");
}


#[test]
fn test_next() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set_mut.add_item(signer_storage2);

    let next = linked_set.next(signer_storage1).unwrap();
    assert_eq!(next.id(), signer_storage2.id());

    assert!(linked_set.next(signer_storage2).is_none(), "Next of last item should be None");
}

#[test]
fn test_item_id_before() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set_mut.add_item(signer_storage2);

    assert_eq!(linked_set.item_id_before(signer_storage2.id()), signer_storage1.id());
    assert_eq!(linked_set.item_id_before(signer_storage1.id()), 0);
}

#[test]
fn test_load() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    let (len, last_id) = linked_set.load();
    assert_eq!(len, 0);
    assert_eq!(last_id, 0);

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    let (len, last_id) = linked_set.load();
    assert_eq!(len, 1);
    assert_eq!(last_id, signer_storage1.id());
}

#[test]
fn test_get_all_ids() {
    let (linked_set_mut, linked_set) = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set_mut.add_item(signer_storage2);

    let ids = linked_set.get_all_ids();
    assert_eq!(ids.len(), 2);
    assert_eq!(*ids[0], signer_storage1.id());
    assert_eq!(*ids[1], signer_storage2.id());
}

#[test]
fn test_read() {
    let (linked_set_mut, _) = setup_linked_set();

    let owner = starknet_signer_from_pubkey(1);
    let signer_storage = owner.storage_value();
    linked_set_mut.add_item(signer_storage);

    let linked_set = linked_set_mut.read();
    assert!(linked_set.is_in(signer_storage), "Read set should contain added item");
}

#[test]
fn test_remove() {
    let (linked_set_mut, _) = setup_linked_set();

    let owner1 = starknet_signer_from_pubkey(1);
    let signer_storage1 = owner1.storage_value();
    linked_set_mut.add_item(signer_storage1);

    let owner2 = starknet_signer_from_pubkey(2);
    let signer_storage2 = owner2.storage_value();
    linked_set_mut.add_item(signer_storage2);

    linked_set_mut.remove(signer_storage1.id());

    let linked_set = linked_set_mut.read();
    assert!(!linked_set.is_in(signer_storage1), "Removed item should not be in set");
    assert!(linked_set.is_in(signer_storage2), "Non-removed item should still be in set");
}


#[test]
fn test_remove_0_1() {
    let (mut component, owners) = setup_three_owners();

    component.remove_owners(array![owners[0].id(), owners[1].id()]);

    let remaining_owners = component.owners_storage().get_all_ids();
    assert_eq!(remaining_owners.len(), 1);
    assert_eq!(*remaining_owners[0], owners[2].id());
}

#[test]
fn test_remove_0_2() {
    let (mut component, owners) = setup_three_owners();

    component.remove_owners(array![owners[0].id(), owners[2].id()]);

    let remaining_owners = component.owners_storage().get_all_ids();
    assert_eq!(remaining_owners.len(), 1);
    assert_eq!(*remaining_owners[0], owners[1].id());
}

#[test]
fn test_remove_1_2() {
    let (mut component, owners) = setup_three_owners();

    component.remove_owners(array![owners[1].id(), owners[2].id()]);

    let remaining_owners = component.owners_storage().get_all_ids();
    assert_eq!(remaining_owners.len(), 1);
    assert_eq!(*remaining_owners[0], owners[0].id());
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn test_remove_0_1_2() {
    let (mut component, owners) = setup_three_owners();

    component.remove_owners(array![owners[0].id(), owners[1].id(), owners[2].id()]);

    let remaining_owners = component.owners_storage().get_all_ids();
    assert_eq!(remaining_owners.len(), 0);
}


#[test]
#[should_panic(expected: ('linked-set/invalid-item',))]
fn test_add_invalid_item() {
    let (linked_set_mut, _) = setup_linked_set();
    let invalid_signer = SignerStorageValue { stored_value: 0, signer_type: SignerType::Starknet };
    linked_set_mut.add_item(invalid_signer);
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn test_add_duplicate_item() {
    let (linked_set_mut, _) = setup_linked_set();
    let owner = starknet_signer_from_pubkey(1);
    let signer_storage = owner.storage_value();
    linked_set_mut.add_item(signer_storage);
    linked_set_mut.add_item(signer_storage);
}

#[test]
#[should_panic(expected: ('linked-set/invalid-id-to-remove',))]
fn test_remove_invalid_id() {
    let (linked_set_mut, _) = setup_linked_set();

    linked_set_mut.remove(0);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn test_remove_non_existent_item() {
    let (linked_set_mut, _) = setup_linked_set();

    let owner = starknet_signer_from_pubkey(1);
    let signer_storage = owner.storage_value();
    linked_set_mut.add_item(signer_storage);

    linked_set_mut.remove(123);
}

#[test]
#[should_panic(expected: ('linked-set/item-after-id',))]
fn test_item_id_before_zero() {
    let (_, linked_set) = setup_linked_set();

    linked_set.item_id_before(0);
}
