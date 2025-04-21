use argent::linked_set::linked_set::{
    LinkedSet, LinkedSetConfig, LinkedSetReadImpl, LinkedSetWriteImpl, MutableLinkedSetReadImpl,
    StorageBaseAsReadOnlyImpl,
};
use argent::utils::array_ext::ArrayExtTrait;
use starknet::Store;
use starknet::storage::{Mutable, StorageAsPath, StorageBase, StoragePath, StoragePointerWriteAccess};

///
/// A LinkedSetWithHead is storage structure that allows to store multiple items making it efficient to check if an item
/// is in the set.
/// LinkedSet doesn't allow duplicate items.
/// The order of the items is preserved.
/// It builds on top of LinkedSet but stores the first item, the head, separately. This means:
/// - Storing just one item is cheap because it doesn't need to store the end marker. Uses the same amount of storage as
/// a LinkedSet for larger sets
/// - Checking if an item is in the set is O(1) complexity. Its a bit more expensive than LinkedSet but
/// still very efficient. It offers better performance than LinkedSet when the set is a single item
///
/// This is how the storage looks like depending on the number of items in the set:
///
/// Storing 1 item:  head=A , tail= []
/// Storing 2 items: head=A , tail= [B]
/// Storing 3 items: head=A , tail= [B, C]
///
#[phantom]
pub struct LinkedSetWithHead<T> {}

pub trait LinkedSetWithHeadRead<TMemberState> {
    type Value;
    /// @returns the first item in the set or None if the set is empty
    fn first(self: TMemberState) -> Option<Self::Value>;
    /// @returns the only item in the set or None if the set is empty or contains more than one item
    fn single(self: TMemberState) -> Option<Self::Value>;
    /// @returns the number of items in the set
    fn len(self: TMemberState) -> usize;
    /// @returns true if the set is empty
    fn is_empty(self: TMemberState) -> bool;
    /// @returns true if the item is in the set
    /// @param item The item to check inclusion
    fn contains(self: TMemberState, item: Self::Value) -> bool;
    /// @returns true if the item is in the set (using the item hash)
    /// @param item_hash The hash of the item to check inclusion
    fn contains_by_hash(self: TMemberState, item_hash: felt252) -> bool;
    /// @returns all the hashes in the set
    fn get_all_hashes(self: TMemberState) -> Array<felt252>;
    /// @returns all the items in the set
    fn get_all(self: TMemberState) -> Array<Self::Value>;
}

pub trait LinkedSetWithHeadWrite<TMemberState> {
    type Value;
    /// Adds an item to the set
    /// @dev It will panic if the item is already in the set
    /// @param item The item to add
    /// @returns the hash of the added item
    fn insert(self: TMemberState, item: Self::Value) -> felt252;
    /// Removes an item from the set
    /// @dev It will panic if the item is not in the set
    /// @param item_hash The hash of the item to remove
    fn remove(self: TMemberState, item_hash: felt252);
}


pub impl LinkedSetWithHeadReadImpl<
    T, +Drop<T>, +Copy<T>, +PartialEq<T>, +starknet::Store<T>, +LinkedSetConfig<T>,
> of LinkedSetWithHeadRead<StorageBase<LinkedSetWithHead<T>>> {
    type Value = T;

    #[inline(always)]
    fn first(self: StorageBase<LinkedSetWithHead<T>>) -> Option<T> {
        LinkedSetConfig::path_read_value(path: self.head_entry())
    }

    fn single(self: StorageBase<LinkedSetWithHead<T>>) -> Option<T> {
        if !self.get_tail_list().is_empty() {
            return Option::None; // More than one item
        }
        self.first()
    }

    fn len(self: StorageBase<LinkedSetWithHead<T>>) -> usize {
        if self.is_empty() {
            return 0;
        }
        1 + self.get_tail_list().len()
    }

    fn is_empty(self: StorageBase<LinkedSetWithHead<T>>) -> bool {
        self.first().is_none()
    }

    fn contains(self: StorageBase<LinkedSetWithHead<T>>, item: T) -> bool {
        let first_item = if let Option::Some(value) = self.first() {
            value
        } else {
            return false; // empty collection
        };

        if first_item == item {
            return true;
        }
        self.get_tail_list().contains(item_hash: item.hash())
    }

    fn contains_by_hash(self: StorageBase<LinkedSetWithHead<T>>, item_hash: felt252) -> bool {
        let first_item = if let Option::Some(value) = self.first() {
            value
        } else {
            return false; // empty collection
        };

        if first_item.hash() == item_hash {
            return true;
        }

        self.get_tail_list().contains(item_hash)
    }

    fn get_all_hashes(self: StorageBase<LinkedSetWithHead<T>>) -> Array<felt252> {
        if let Option::Some(first_item) = self.first() {
            let mut all_hashes = array![first_item.hash()];
            all_hashes.append_all(self.get_tail_list().get_all_hashes().span());
            all_hashes
        } else {
            // empty collection
            array![]
        }
    }

    fn get_all(self: StorageBase<LinkedSetWithHead<T>>) -> Array<T> {
        if let Option::Some(first_item) = self.first() {
            let mut all_items = array![first_item];
            all_items.append_all(self.get_tail_list().get_all().span());
            all_items
        } else {
            // empty collection
            array![]
        }
    }
}

#[generate_trait]
impl LinkedSetWithHeadReadPrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +starknet::Store<T>, +LinkedSetConfig<T>,
> of LinkedSetWithHeadReadPrivate<T> {
    #[inline(always)]
    fn head_entry(self: StorageBase<LinkedSetWithHead<T>>) -> StoragePath<T> {
        StorageBase { __base_address__: self.__base_address__ }.as_path()
    }

    fn get_tail_list(self: StorageBase<LinkedSetWithHead<T>>) -> StorageBase<LinkedSet<T>> {
        StorageBase { __base_address__: self.__base_address__ + 1 }
    }
}

pub impl LinkedSetWithHeadWriteImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>,
> of LinkedSetWithHeadWrite<StorageBase<Mutable<LinkedSetWithHead<T>>>> {
    type Value = T;

    fn insert(self: StorageBase<Mutable<LinkedSetWithHead<T>>>, item: T) -> felt252 {
        if let Option::Some(first_item) = self.first() {
            assert(item != first_item, 'linked-set/already-in-set');
            self.get_tail_list().insert(item)
        } else {
            // Empty list
            assert(item.is_valid_item(), 'linked-set/invalid-item');
            self.head_entry().write(item);
            item.hash()
        }
    }

    fn remove(self: StorageBase<Mutable<LinkedSetWithHead<T>>>, item_hash: felt252) {
        let head_item = self.first().expect('linked-set/item-not-found');
        if head_item.hash() == item_hash {
            // Removing head item
            let first_in_tail = self.get_tail_list().first();
            if let Option::Some(first_in_tail) = first_in_tail {
                // Move first tail item to the head
                self.head_entry().write(first_in_tail); // overwrite the head
                self.get_tail_list().remove(first_in_tail.hash());
            } else {
                // Tail is empty. Remove the head and leave an empty set
                self.head_entry().write(Default::default());
            }
        } else {
            // Item is not the head
            self.get_tail_list().remove(item_hash);
        };
    }
}

#[generate_trait]
impl LinkedSetWithHeadWritePrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>,
> of LinkedSetWithHeadWritePrivate<T> {
    fn head_entry(self: StorageBase<Mutable<LinkedSetWithHead<T>>>) -> StoragePath<Mutable<T>> {
        StorageBase { __base_address__: self.__base_address__ }.as_path()
    }

    fn get_tail_list(self: StorageBase<Mutable<LinkedSetWithHead<T>>>) -> StorageBase<Mutable<LinkedSet<T>>> {
        StorageBase { __base_address__: self.__base_address__ + 1 }
    }
}

// Allow read operations in mutable access too
pub impl MutableLinkedSetWithHeadReadImpl<
    T, +Drop<T>, +Copy<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>,
> of LinkedSetWithHeadRead<StorageBase<Mutable<LinkedSetWithHead<T>>>> {
    type Value = T;

    fn first(self: StorageBase<Mutable<LinkedSetWithHead<T>>>) -> Option<T> {
        self.as_read_only().first()
    }

    fn single(self: StorageBase<Mutable<LinkedSetWithHead<T>>>) -> Option<T> {
        self.as_read_only().single()
    }

    fn len(self: StorageBase<Mutable<LinkedSetWithHead<T>>>) -> usize {
        self.as_read_only().len()
    }

    fn is_empty(self: StorageBase<Mutable<LinkedSetWithHead<T>>>) -> bool {
        self.as_read_only().is_empty()
    }

    fn contains(self: StorageBase<Mutable<LinkedSetWithHead<T>>>, item: T) -> bool {
        self.as_read_only().contains(:item)
    }

    fn contains_by_hash(self: StorageBase<Mutable<LinkedSetWithHead<T>>>, item_hash: felt252) -> bool {
        self.as_read_only().contains_by_hash(:item_hash)
    }

    fn get_all_hashes(self: StorageBase<Mutable<LinkedSetWithHead<T>>>) -> Array<felt252> {
        self.as_read_only().get_all_hashes()
    }

    fn get_all(self: StorageBase<Mutable<LinkedSetWithHead<T>>>) -> Array<T> {
        self.as_read_only().get_all()
    }
}
