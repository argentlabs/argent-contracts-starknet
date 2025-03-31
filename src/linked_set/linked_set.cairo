use starknet::Store;
use starknet::storage::{
    Mutable, PendingStoragePathTrait, StorageAsPath, StorageBase, StoragePath, StoragePointerWriteAccess,
};
///
/// A LinkedSet is storage structure that allows to store multiple items making it efficient to check if an item is in
/// the set. LinkedSet doesn't allow duplicate items. The order of the items is preserved.
/// In terms of storage. It will use the same number of storage slots as storing all items in succession plus the
/// equivalent of another item to store the end marker.
/// Searching a given item in the list can be done with O(1) complexity, that means that we only need to check the
/// storage once regardless of the set size. Items on the list must provide a hash function. So each item provides a
/// unique hash.
/// The implementation is based on a having one item "pointing" at the next one. 0 points to the first item, and the
/// last item points to the end marker.
///
/// If we have the items A, B and C the memory will look like this
///
/// storage address ->    value
/// -------------------------------
///        0        ->      A
///      hash(A)    ->      B
///      hash(B)    ->      C
///      hash(C)    ->  END_MARKER
///
///
/// It is critical that the hash function is uniformly distributed, because if the hash returned is invalid it might
/// corrupt the set. For instance if the hash returns the values 1,2,3 for the items A,B,C and storing each item uses 2
/// storage slots, when writing one item we might be overriding the storage of other items
///
#[phantom]
pub struct LinkedSet<T> {}

pub trait LinkedSetRead<TMemberState> {
    type Value;
    /// @return number of items in the set
    fn len(self: TMemberState) -> usize;
    /// @return true if the set has no items
    fn is_empty(self: TMemberState) -> bool;
    /// @return true if the item is in the set
    /// @param item_hash the hash of the item to check
    fn contains(self: TMemberState, item_hash: felt252) -> bool;
    /// @return first item on the set or None if the set is empty
    fn first(self: TMemberState) -> Option<Self::Value>;
    /// @return the hashes of all items in the set
    fn get_all_hashes(self: TMemberState) -> Array<felt252>;
    /// @returns all the items in the set
    fn get_all(self: TMemberState) -> Array<Self::Value>;
}

pub trait LinkedSetWrite<TMemberState> {
    type Value;
    /// Adds an item at the end of the set.
    /// @dev It will panic if the item is already in the set
    /// @returns the hash of the inserted item which is now the latest item on the list
    /// @param item the item to add
    fn insert(self: TMemberState, item: Self::Value) -> felt252;
    /// Adds multiple items to the end of the set.
    /// @dev It will panic if any of the items is already in the set
    /// @param items_to_add the items to add
    fn insert_many(self: TMemberState, items_to_add: Span<Self::Value>);
    /// Removes an item from the set.
    /// @dev It will panic if the item is not in the set
    /// @param item_hash the hash of the item to remove
    fn remove(self: TMemberState, item_hash: felt252);
    /// Removes multiple items from the set.
    /// @dev It will panic if any of the items is not in the set
    /// @param items_hashes_to_remove the hashes of the items to remove
    fn remove_many(self: TMemberState, items_hashes_to_remove: Span<felt252>);
}

///
/// Needed to setup a LinkedSet for a given type
/// The implementation must be correct otherwise it might corrupt the set
///
pub trait LinkedSetConfig<T> {
    /// An item that represent the end of the list. It must be an invalid item according to the `is_valid_item` function
    const END_MARKER: T;

    // Check if the item is valid. Otherwise it can't be added to the set
    fn is_valid_item(self: @T) -> bool;

    /// @notice returns a unique hash for the given item. The hash can't be zero as it's reserved for the first item
    /// @dev It is critical that the hash function is uniformly distributed, because if the hash returned is invalid it
    /// might corrupt the set. For instance if the hash returns the values 1,2,3 for the items A,B,C and storing each
    /// item uses 2 storage slots. when writing one item we might e overriding the storage of other items
    /// @param self the item to hash
    /// @return the item hash
    fn hash(self: @T) -> felt252;

    // @notice reads the value stored at the given StoragePath
    // @dev must return valid items according to the `is_valid_item` function
    // @param path the path to read
    // @returns the value stored at the given path or None if the path is empty
    fn path_read_value(path: StoragePath<T>) -> Option<T>;

    // @return true when the value stored in the given path is valid or the end marker
    // @param path the path determined by the hash of the item we want to check inclusion
    fn path_is_in_set(path: StoragePath<T>) -> bool;
}

///
/// Used to add the end marker.
/// For upgrade purposes only
/// The implementation must be correct to avoid corrupting the linked set
///
pub trait IAddEndMarker<TMemberState> {
    /// @notice This is used during upgrades to ensure the linked set is correctly terminated.
    fn add_end_marker(self: TMemberState);
}

impl AddEndMarkerImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>,
> of IAddEndMarker<StorageBase<Mutable<LinkedSet<T>>>> {
    fn add_end_marker(self: StorageBase<Mutable<LinkedSet<T>>>) {
        let last_signer = self.find_last_hash();
        if last_signer != 0 {
            self.entry(last_signer).write(LinkedSetConfig::END_MARKER);
        }
    }
}

pub impl LinkedSetReadImpl<
    T, +Drop<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>,
> of LinkedSetRead<StorageBase<LinkedSet<T>>> {
    type Value = T;

    fn is_empty(self: StorageBase<LinkedSet<T>>) -> bool {
        self.first().is_none()
    }

    fn contains(self: StorageBase<LinkedSet<T>>, item_hash: felt252) -> bool {
        if item_hash == 0 {
            return false;
        }
        LinkedSetConfig::path_is_in_set(path: self.entry(item_hash))
    }

    fn len(self: StorageBase<LinkedSet<T>>) -> usize {
        let mut current_item_hash = 0;
        let mut size = 0;
        while let Option::Some(next_item) = self.next(current_item_hash) {
            current_item_hash = next_item.hash();
            size += 1;
        };
        size
    }

    fn first(self: StorageBase<LinkedSet<T>>) -> Option<T> {
        self.next(item_hash: 0)
    }

    fn get_all_hashes(self: StorageBase<LinkedSet<T>>) -> Array<felt252> {
        let mut current_item_hash = 0;
        let mut all_hashes = array![];
        while let Option::Some(next_item) = self.next(current_item_hash) {
            current_item_hash = next_item.hash();
            all_hashes.append(current_item_hash);
        };
        all_hashes
    }

    fn get_all(self: StorageBase<LinkedSet<T>>) -> Array<T> {
        let mut current_item_hash = 0;
        let mut all_items = array![];
        while let Option::Some(next_item) = self.next(current_item_hash) {
            current_item_hash = next_item.hash();
            all_items.append(next_item);
        };
        all_items
    }
}

#[generate_trait]
pub impl LinkedSetReadPrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>,
> of LinkedSetReadPrivate<T> {
    fn entry(self: StorageBase<LinkedSet<T>>, item_hash: felt252) -> StoragePath<T> {
        PendingStoragePathTrait::new(@self.as_path(), item_hash).as_path()
    }

    fn next(self: StorageBase<LinkedSet<T>>, item_hash: felt252) -> Option<T> {
        LinkedSetConfig::path_read_value(path: self.entry(item_hash))
    }

    // Return the last item hash or zero when the list is empty. Cost increases with the list size
    fn find_last_hash(self: StorageBase<LinkedSet<T>>) -> felt252 {
        let mut current_item_hash = 0;
        while let Option::Some(next_item) = self.next(current_item_hash) {
            current_item_hash = next_item.hash();
        };
        current_item_hash
    }

    fn item_hash_before(self: StorageBase<LinkedSet<T>>, item_hash_after: felt252) -> felt252 {
        assert(item_hash_after != 0, 'linked-set/item-hash-after');
        let mut current_item_hash = 0;
        loop {
            let next_item = self.next(current_item_hash).expect('linked-set/item-not-found');
            let next_item_hash = next_item.hash();
            if next_item_hash == item_hash_after {
                break current_item_hash;
            }
            current_item_hash = next_item_hash;
        }
    }
}

pub impl LinkedSetWriteImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>,
> of LinkedSetWrite<StorageBase<Mutable<LinkedSet<T>>>> {
    type Value = T;

    fn insert(self: StorageBase<Mutable<LinkedSet<T>>>, item: T) -> felt252 {
        self.insert_opt(:item, last_item_hash: self.find_last_hash())
    }

    fn insert_many(self: StorageBase<Mutable<LinkedSet<T>>>, items_to_add: Span<T>) {
        let mut last_item_hash: felt252 = self.find_last_hash();
        for item in items_to_add {
            last_item_hash = self.insert_opt(item: *item, :last_item_hash);
        };
    }

    fn remove_many(self: StorageBase<Mutable<LinkedSet<T>>>, items_hashes_to_remove: Span<felt252>) {
        for item_hash in items_hashes_to_remove {
            self.remove(item_hash: *item_hash);
        };
    }

    fn remove(self: StorageBase<Mutable<LinkedSet<T>>>, item_hash: felt252) {
        assert(item_hash != 0, 'linked-set/invalid-hash-to-rem');

        // Previous item set to the next item in the list
        let previous_item_hash = self.item_hash_before(item_hash);

        if let Option::Some(next_item) = self.next(item_hash) {
            // Removing an item in the middle
            self.entry(previous_item_hash).write(next_item);
        } else {
            // Removing the last item
            self.entry(previous_item_hash).write(LinkedSetConfig::END_MARKER);
        }
        // removed pointer set to empty
        self.entry(item_hash).write(Default::default());
    }
}

#[generate_trait]
pub impl LinkedSetWritePrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>,
> of LinkedSetWritePrivate<T> {
    fn entry(self: StorageBase<Mutable<LinkedSet<T>>>, item_hash: felt252) -> StoragePath<Mutable<T>> {
        PendingStoragePathTrait::new(@self.as_path(), item_hash).as_path()
    }

    fn insert_opt(self: StorageBase<Mutable<LinkedSet<T>>>, item: T, last_item_hash: felt252) -> felt252 {
        assert(item.is_valid_item(), 'linked-set/invalid-item');
        let item_hash = item.hash();
        let is_duplicate = self.contains(:item_hash);
        assert(!is_duplicate, 'linked-set/already-in-set');
        self.entry(last_item_hash).write(item);
        self.entry(item_hash).write(LinkedSetConfig::END_MARKER);
        item_hash
    }

    // Allow easy access to the read-only version of the storage
    fn item_hash_before(self: StorageBase<Mutable<LinkedSet<T>>>, item_hash_after: felt252) -> felt252 {
        self.as_read_only().item_hash_before(:item_hash_after)
    }

    fn next(self: StorageBase<Mutable<LinkedSet<T>>>, item_hash: felt252) -> Option<T> {
        self.as_read_only().next(:item_hash)
    }

    fn find_last_hash(self: StorageBase<Mutable<LinkedSet<T>>>) -> felt252 {
        self.as_read_only().find_last_hash()
    }
}

#[generate_trait]
pub impl StorageBaseAsReadOnlyImpl<T> of StorageBaseAsReadOnly<T> {
    fn as_read_only(self: StorageBase<Mutable<T>>) -> StorageBase<T> {
        StorageBase { __base_address__: self.__base_address__ }
    }
}

// Allow read operations in mutable access too
pub impl MutableLinkedSetReadImpl<
    T, +Drop<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>,
> of LinkedSetRead<StorageBase<Mutable<LinkedSet<T>>>> {
    type Value = T;

    fn is_empty(self: StorageBase<Mutable<LinkedSet<T>>>) -> bool {
        self.as_read_only().is_empty()
    }

    fn contains(self: StorageBase<Mutable<LinkedSet<T>>>, item_hash: felt252) -> bool {
        self.as_read_only().contains(:item_hash)
    }

    fn len(self: StorageBase<Mutable<LinkedSet<T>>>) -> usize {
        self.as_read_only().len()
    }

    fn first(self: StorageBase<Mutable<LinkedSet<T>>>) -> Option<T> {
        self.as_read_only().first()
    }

    fn get_all_hashes(self: StorageBase<Mutable<LinkedSet<T>>>) -> Array<felt252> {
        self.as_read_only().get_all_hashes()
    }

    fn get_all(self: StorageBase<Mutable<LinkedSet<T>>>) -> Array<T> {
        self.as_read_only().get_all()
    }
}
