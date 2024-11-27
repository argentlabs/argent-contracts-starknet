use argent::utils::array_ext::ArrayExt;
use starknet::Store;
use starknet::storage::{StorageAsPath, StoragePathEntry, StoragePathTrait, StoragePath, Mutable, StorageBase};
use super::linked_set::{
    LinkedSet, LinkedSetConfig, LinkedSetReadImpl, LinkedSetWriteImpl, MutableLinkedSetReadImpl,
    StorageBaseAsReadOnlyImpl
};


#[phantom]
pub struct LinkedSetPlus1<T> {}

pub trait LinkedSetPlus1Read<TMemberState> {
    type Value;
    fn first(self: TMemberState) -> Option<Self::Value>;
    fn len(self: TMemberState) -> usize;
    fn is_empty(self: TMemberState) -> bool;
    fn is_in(self: TMemberState, item: Self::Value) -> bool;
    fn is_in_id(self: TMemberState, item_id: felt252) -> bool;
    fn get_all_ids(self: TMemberState) -> Array<felt252>;
}

pub trait LinkedSetPlus1Write<TMemberState> {
    type Value;
    // returns the id of the added item
    fn add_item(self: TMemberState, item: Self::Value) -> felt252;
    fn remove(self: TMemberState, remove_id: felt252);
}


impl LinkedSetPlus1ReadImpl<
    T, +Drop<T>, +PartialEq<T>, +starknet::Store<T>, +LinkedSetConfig<T>
> of LinkedSetPlus1Read<StorageBase<LinkedSetPlus1<T>>> {
    type Value = T;

    fn first(self: StorageBase<LinkedSetPlus1<T>>) -> Option<T> {
        LinkedSetConfig::path_read_value(path: self.head_entry())
    }

    fn len(self: StorageBase<LinkedSetPlus1<T>>) -> usize {
        if self.is_empty() {
            return 0;
        }
        1 + self.get_tail_list().len()
    }

    fn is_empty(self: StorageBase<LinkedSetPlus1<T>>) -> bool {
        self.first().is_none()
    }

    fn is_in(self: StorageBase<LinkedSetPlus1<T>>, item: T) -> bool {
        if !item.is_valid_item() {
            return false;
        }
        let first_item = if let Option::Some(value) = self.first() {
            value
        } else {
            return false; // empty collection
        };

        if first_item == item {
            return true;
        }
        self.get_tail_list().is_in(item)
    }

    fn is_in_id(self: StorageBase<LinkedSetPlus1<T>>, item_id: felt252) -> bool {
        if item_id == 0 {
            return false;
        }

        let first_item = if let Option::Some(value) = self.first() {
            value
        } else {
            return false; // empty collection
        };

        if first_item.id() == item_id {
            return true;
        }

        self.get_tail_list().is_in_id(item_id)
    }

    fn get_all_ids(self: StorageBase<LinkedSetPlus1<T>>) -> Array<felt252> {
        let first_item = if let Option::Some(value) = self.first() {
            value
        } else {
            return array![]; // empty collection
        };
        let mut all_ids = array![first_item.id()];
        all_ids.append_all(self.get_tail_list().get_all_ids().span());
        all_ids
    }
}

#[generate_trait]
impl LinkedSetPlus1ReadPrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +starknet::Store<T>, +LinkedSetConfig<T>
> of LinkedSetPlus1ReadPrivate<T> {
    fn head_entry(self: StorageBase<LinkedSetPlus1<T>>) -> StoragePath<T> {
        StoragePathTrait::new(self.as_path().__hash_state__.state)
    }
    fn get_tail_list(self: StorageBase<LinkedSetPlus1<T>>) -> StorageBase<LinkedSet<T>> {
        StorageBase { __base_address__: self.__base_address__ }
    }
}

impl LinkedSetPlus1WriteImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>
> of LinkedSetPlus1Write<StorageBase<Mutable<LinkedSetPlus1<T>>>> {
    type Value = T;

    fn add_item(self: StorageBase<Mutable<LinkedSetPlus1<T>>>, item: T) -> felt252 {
        assert(item.is_valid_item(), 'linked-set/invalid-item');

        if let Option::Some(first_item) = self.first() {
            assert(item != first_item, 'linked-set/already-in-set');
            self.get_tail_list().add_item(item)
        } else {
            // Empty list
            self.head_entry().write(item);
            item.id()
        }
    }

    fn remove(self: StorageBase<Mutable<LinkedSetPlus1<T>>>, remove_id: felt252) {
        assert(remove_id != 0, 'linked-set/invalid-id-to-remove');
        let head_item = self.first().expect('linked-set/item-not-found');
        if head_item.id() == remove_id {
            // Removing head item
            let first_in_tail = self.get_tail_list().first();
            if let Option::Some(first_in_tail) = first_in_tail {
                // Move first tail item to the head
                self.head_entry().write(first_in_tail); // overwrite the head
                self.get_tail_list().remove(first_in_tail.id());
            } else {
                // Tail is empty. Remove the head and leave an empty set
                self.head_entry().write(Default::default());
            }
        } else {
            // Item is not the head
            self.get_tail_list().remove(remove_id);
        };
    }
}

#[generate_trait]
impl LinkedSetPlus1WritePrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>
> of LinkedSetPlus1WritePrivate<T> {
    fn head_entry(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> StoragePath<Mutable<T>> {
        StoragePathTrait::new(self.as_path().__hash_state__.state)
    }
    fn get_tail_list(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> StorageBase<Mutable<LinkedSet<T>>> {
        StorageBase { __base_address__: self.__base_address__ }
    }
}

// Allow read operations in mutable access too
impl MutableLinkedSetPlus1ReadImpl<
    T, +Drop<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>,
> of LinkedSetPlus1Read<StorageBase<Mutable<LinkedSetPlus1<T>>>> {
    type Value = T;

    fn first(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> Option<T> {
        self.as_read_only().first()
    }

    fn len(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> usize {
        self.as_read_only().len()
    }

    fn is_empty(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> bool {
        self.as_read_only().is_empty()
    }

    fn is_in(self: StorageBase<Mutable<LinkedSetPlus1<T>>>, item: T) -> bool {
        self.as_read_only().is_in(item)
    }

    fn is_in_id(self: StorageBase<Mutable<LinkedSetPlus1<T>>>, item_id: felt252) -> bool {
        self.as_read_only().is_in_id(item_id)
    }

    fn get_all_ids(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> Array<felt252> {
        self.as_read_only().get_all_ids()
    }
}
