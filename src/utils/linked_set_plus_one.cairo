use argent::utils::array_ext::ArrayExt;
use starknet::Store;
use starknet::storage::{StorageAsPath, StoragePathEntry, StoragePathTrait, StoragePath, Mutable, StorageBase};
use super::linked_set::{
    LinkedSet, LinkedSetConfig, LinkedSetReadImpl, LinkedSetWriteImpl, MutableLinkedSetReadImpl,
    StorageBaseAsReadOnlyImpl
};

///
/// A LinkedSetPlus1 is storage structure that allows to store multiple items making it efficient to check if an item is
/// on the set LinkedSet doesn't allow duplicate items. The order of the items is preserved.
/// It builds on top of LinkedSet but stores the first item separately. This means:
/// - Storing just one item is cheap because it doesn't need to store the end marker. Uses the same amount of storage
/// for larger sets - Checking if an item is in the set is O(1) complexity. Its a bit more expensive than LinkedSet but
/// still very efficient. It offers better performance than LinkedSet when the set is a single item
///
#[phantom]
pub struct LinkedSetPlus1<T> {}

pub trait LinkedSetPlus1Read<TMemberState> {
    type Value;
    /// @returns the first item in the set or None if the set is empty
    fn first(self: TMemberState) -> Option<Self::Value>;
    /// @returns the number of items in the set
    fn len(self: TMemberState) -> usize;
    /// @returns true if the set is empty
    fn is_empty(self: TMemberState) -> bool;
    /// @returns true if the item is in the set
    /// @param item The item to check inclusion
    fn is_in(self: TMemberState, item: Self::Value) -> bool;
    /// @returns true if the item is in the set
    /// @param item_hash The hash of the item to check inclusion
    fn is_in_hash(self: TMemberState, item_hash: felt252) -> bool;
    /// @returns all the hashes in the set
    fn get_all_hashes(self: TMemberState) -> Array<felt252>;
}

pub trait LinkedSetPlus1Write<TMemberState> {
    type Value;
    /// Adds an item to the set, it will panic if the item is already in the set
    /// @param item The item to add
    /// @returns the hash of the added item
    fn add_item(self: TMemberState, item: Self::Value) -> felt252;
    /// Removes an item from the set, it will panic if the item is not in the set
    /// @param item_hash The hash of the item to remove
    fn remove_item(self: TMemberState, item_hash: felt252);
}


impl LinkedSetPlus1ReadImpl<
    T, +Drop<T>, +PartialEq<T>, +starknet::Store<T>, +LinkedSetConfig<T>
> of LinkedSetPlus1Read<StorageBase<LinkedSetPlus1<T>>> {
    type Value = T;

    #[inline(always)]
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

    #[inline(always)]
    fn is_in(self: StorageBase<LinkedSetPlus1<T>>, item: T) -> bool {
        let first_item = if let Option::Some(value) = self.first() {
            value
        } else {
            return false; // empty collection
        };

        if first_item == item {
            return true;
        }
        self.get_tail_list().is_in(item_hash: item.hash())
    }

    #[inline(always)]
    fn is_in_hash(self: StorageBase<LinkedSetPlus1<T>>, item_hash: felt252) -> bool {
        let first_item = if let Option::Some(value) = self.first() {
            value
        } else {
            return false; // empty collection
        };

        if first_item.hash() == item_hash {
            return true;
        }

        self.get_tail_list().is_in(item_hash)
    }

    fn get_all_hashes(self: StorageBase<LinkedSetPlus1<T>>) -> Array<felt252> {
        let first_item = if let Option::Some(value) = self.first() {
            value
        } else {
            return array![]; // empty collection
        };
        let mut all_hashes = array![first_item.hash()];
        all_hashes.append_all(self.get_tail_list().get_all_hashes().span());
        all_hashes
    }
}

#[generate_trait]
impl LinkedSetPlus1ReadPrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +starknet::Store<T>, +LinkedSetConfig<T>
> of LinkedSetPlus1ReadPrivate<T> {
    #[inline(always)]
    fn head_entry(self: StorageBase<LinkedSetPlus1<T>>) -> StoragePath<T> {
        StoragePathTrait::new(self.as_path().__hash_state__.state)
    }

    #[inline(always)]
    fn get_tail_list(self: StorageBase<LinkedSetPlus1<T>>) -> StorageBase<LinkedSet<T>> {
        StorageBase { __base_address__: self.__base_address__ }
    }
}

impl LinkedSetPlus1WriteImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>
> of LinkedSetPlus1Write<StorageBase<Mutable<LinkedSetPlus1<T>>>> {
    type Value = T;

    #[inline(always)]
    fn add_item(self: StorageBase<Mutable<LinkedSetPlus1<T>>>, item: T) -> felt252 {
        if let Option::Some(first_item) = self.first() {
            assert(item != first_item, 'linked-set/already-in-set');
            self.get_tail_list().add_item(item)
        } else {
            // Empty list
            assert(item.is_valid_item(), 'linked-set/invalid-item');
            self.head_entry().write(item);
            item.hash()
        }
    }

    fn remove_item(self: StorageBase<Mutable<LinkedSetPlus1<T>>>, item_hash: felt252) {
        let head_item = self.first().expect('linked-set/item-not-found');
        if head_item.hash() == item_hash {
            // Removing head item
            let first_in_tail = self.get_tail_list().first();
            if let Option::Some(first_in_tail) = first_in_tail {
                // Move first tail item to the head
                self.head_entry().write(first_in_tail); // overwrite the head
                self.get_tail_list().remove_item(first_in_tail.hash());
            } else {
                // Tail is empty. Remove the head and leave an empty set
                self.head_entry().write(Default::default());
            }
        } else {
            // Item is not the head
            self.get_tail_list().remove_item(item_hash);
        };
    }
}

#[generate_trait]
impl LinkedSetPlus1WritePrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>
> of LinkedSetPlus1WritePrivate<T> {
    #[inline(always)]
    fn head_entry(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> StoragePath<Mutable<T>> {
        StoragePathTrait::new(self.as_path().__hash_state__.state)
    }

    #[inline(always)]
    fn get_tail_list(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> StorageBase<Mutable<LinkedSet<T>>> {
        StorageBase { __base_address__: self.__base_address__ }
    }
}

// Allow read operations in mutable access too
impl MutableLinkedSetPlus1ReadImpl<
    T, +Drop<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>,
> of LinkedSetPlus1Read<StorageBase<Mutable<LinkedSetPlus1<T>>>> {
    type Value = T;

    #[inline(always)]
    fn first(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> Option<T> {
        self.as_read_only().first()
    }

    #[inline(always)]
    fn len(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> usize {
        self.as_read_only().len()
    }

    #[inline(always)]
    fn is_empty(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> bool {
        self.as_read_only().is_empty()
    }

    #[inline(always)]
    fn is_in(self: StorageBase<Mutable<LinkedSetPlus1<T>>>, item: T) -> bool {
        self.as_read_only().is_in(:item)
    }

    #[inline(always)]
    fn is_in_hash(self: StorageBase<Mutable<LinkedSetPlus1<T>>>, item_hash: felt252) -> bool {
        self.as_read_only().is_in_hash(:item_hash)
    }

    #[inline(always)]
    fn get_all_hashes(self: StorageBase<Mutable<LinkedSetPlus1<T>>>) -> Array<felt252> {
        self.as_read_only().get_all_hashes()
    }
}
