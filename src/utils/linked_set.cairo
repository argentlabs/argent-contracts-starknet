use starknet::Store;
use starknet::storage::{StoragePathEntry, StoragePath, Mutable, StoragePathUpdateTrait, StorageBase};

pub trait SetItem<T> {
    // TODO rename? this is needed mostly to check if the result of reading storage is valid, but also to ensure we
    // don't store invalid items
    fn is_valid_item(self: @T) -> bool;
    // can't be zero unless it's an invalid item, actually it should never be called on an invalid item, maybe can
    // return NonZero<felt252>? also add a note that the ids must be unique
    fn id(self: @T) -> felt252;
}

#[phantom]
pub struct LinkedSet<T> {}

impl EntryInfoLinkedSet<T> of StoragePathEntry<StoragePath<LinkedSet<T>>> {
    type Key = felt252;
    type Value = T;

    fn entry(self: StoragePath<LinkedSet<T>>, key: felt252) -> StoragePath<T> {
        self.update(key)
    }
}

impl MutableEntryInfoLinkedSet<T> of StoragePathEntry<StoragePath<Mutable<LinkedSet<T>>>> {
    type Key = felt252;
    type Value = Mutable<T>;
    fn entry(self: StoragePath<Mutable<LinkedSet<T>>>, key: felt252) -> StoragePath<Mutable<T>> {
        self.update(key)
    }
}

/// Trait for reading a contract/component storage member in a specific key place.
pub trait LinkedSetRead<TMemberState> {
    type Value;
    fn len(self: TMemberState) -> usize;
    fn is_empty(self: TMemberState) -> bool;
    fn is_in(self: TMemberState, item: Self::Value) -> bool;
    fn is_in_id(self: TMemberState, item_id: felt252) -> bool;
    fn is_in_id_using_last(self: TMemberState, item_id: felt252, last_item_id: felt252) -> bool;
    fn find_last_id(self: TMemberState) -> felt252;
    fn first(self: TMemberState) -> Option<Self::Value>;
    // Returns the first item if there is one item in the list, otherwise returns None
    fn single(self: TMemberState) -> Option<Self::Value>;
    fn next(self: TMemberState, item_id: felt252) -> Option<Self::Value>;
    fn item_id_before(self: TMemberState, item_after_id: felt252) -> felt252;
    // Returns the set size and the last item id (or zero if empty)
    fn load(self: TMemberState) -> (usize, felt252);
    fn get_all_ids(self: TMemberState) -> Array<felt252>;
}

/// Trait for reading a contract/component storage member in a specific key place.
pub trait LinkedSetWrite<TMemberState> {
    type Value;
    fn remove(self: TMemberState, remove_id: felt252);
    // Returns the last item of the list after the removal
    fn remove_opt(self: TMemberState, remove_id: felt252, last_item_id: felt252) -> felt252;
    /// @returns the id of the inserted item which is now the latest item on the list
    fn add_item(self: TMemberState, item: Self::Value) -> felt252;
    /// @returns the id of the inserted item which is now the latest item on the list
    fn add_item_opt(self: TMemberState, item: Self::Value, last_item_id: felt252) -> felt252;
    fn add_items(self: TMemberState, items_to_add: Span<Self::Value>, last_item_id: felt252);
    fn remove_items(self: TMemberState, items_ids_to_remove: Span<felt252>, last_item_id: felt252);

    /// @notice Replace one item with a different one
    /// @dev Will revert when trying to remove an item that isn't in the list
    /// @dev Will revert when trying to add an item that is in the list or if the item is invalid
    /// @dev Will revert if both items are the same
    /// @param item_id_to_remove Id of the item to remove
    /// @param item_to_add Item to add
    fn replace_item(self: TMemberState, item_id_to_remove: felt252, item_to_add: Self::Value);
}

impl LinkedSetReadImpl<T, +Drop<T>, +starknet::Store<T>, +SetItem<T>> of LinkedSetRead<StorageBase<LinkedSet<T>>> {
    type Value = T;

    fn is_empty(self: StorageBase<LinkedSet<T>>) -> bool {
        self.first().is_none()
    }

    fn is_in(self: StorageBase<LinkedSet<T>>, item: T) -> bool {
        if !item.is_valid_item() {
            return false;
        }
        self.is_in_id(item.id())
    }

    fn is_in_id(self: StorageBase<LinkedSet<T>>, item_id: felt252) -> bool {
        if item_id == 0 {
            return false;
        }
        if self.next(item_id).is_some() {
            return true;
        }
        // check if its the latest. This is a bit better than calling find_last_id
        let mut current_item_id = 0;
        loop {
            if let Option::Some(next_item) = self.next(current_item_id) {
                current_item_id = next_item.id();
                if current_item_id == item_id {
                    break true;
                }
            } else {
                break false;
            }
        }
    }

    fn is_in_id_using_last(self: StorageBase<LinkedSet<T>>, item_id: felt252, last_item_id: felt252) -> bool {
        if item_id == 0 {
            return false;
        }
        if self.next(item_id).is_some() {
            return true;
        }
        // check if its the latest
        self.find_last_id() == item_id
    }

    // Return the last item id or zero when the list is empty. Cost increases with the list size
    fn find_last_id(self: StorageBase<LinkedSet<T>>) -> felt252 {
        let mut current_item_id = 0;
        loop {
            if let Option::Some(next_item) = self.next(current_item_id) {
                current_item_id = next_item.id();
            } else {
                break current_item_id;
            }
        }
    }

    fn len(self: StorageBase<LinkedSet<T>>) -> usize {
        let (len, _) = self.load();
        len
    }

    // Returns the number of signers and the last item id (or zero if the list is empty). Cost
    // increases with the list size
    /// returns (len, last_item_id)
    fn load(self: StorageBase<LinkedSet<T>>) -> (usize, felt252) {
        let mut current_item_id = 0;
        let mut size = 0;
        loop {
            if let Option::Some(next_item) = self.next(current_item_id) {
                current_item_id = next_item.id();
                size += 1;
            } else {
                break (size, current_item_id);
            }
        }
    }

    fn first(self: StorageBase<LinkedSet<T>>) -> Option<T> {
        self.next(0)
    }

    fn single(self: StorageBase<LinkedSet<T>>) -> Option<T> {
        let first_item = self.first()?;
        if self.next(first_item.id()).is_some() {
            // More than one item in the list
            Option::None
        } else {
            Option::Some(first_item)
        }
    }

    fn next(self: StorageBase<LinkedSet<T>>, item_id: felt252) -> Option<T> {
        let next_item = self.entry(item_id).read();
        if !next_item.is_valid_item() {
            Option::None
        } else {
            Option::Some(next_item)
        }
    }

    fn item_id_before(self: StorageBase<LinkedSet<T>>, item_after_id: felt252) -> felt252 {
        assert(item_after_id != 0, 'linked-set/item-after-id');
        let mut current_item_id = 0;
        loop {
            let next_item = self.next(current_item_id).expect('linked-set/item-not-found');
            let next_item_id = next_item.id();
            if next_item_id == item_after_id {
                break current_item_id;
            }
            current_item_id = next_item_id;
        }
    }

    fn get_all_ids(self: StorageBase<LinkedSet<T>>) -> Array<felt252> {
        let mut current_item_id = 0;
        let mut all_ids = array![];
        loop {
            if let Option::Some(next_item) = self.next(current_item_id) {
                current_item_id = next_item.id();
                all_ids.append(current_item_id);
            } else {
                break;
            }
        };
        all_ids
    }
}

impl LinkedSetWriteImpl<
    T, +Drop<T>, +Copy<T>, +Store<T>, +SetItem<T>, +Default<T>
> of LinkedSetWrite<StorageBase<Mutable<LinkedSet<T>>>> {
    type Value = T;

    fn add_item(self: StorageBase<Mutable<LinkedSet<T>>>, item: T) -> felt252 {
        self.add_item_opt(:item, last_item_id: self.find_last_id())
    }

    fn add_item_opt(self: StorageBase<Mutable<LinkedSet<T>>>, item: T, last_item_id: felt252) -> felt252 {
        assert(item.is_valid_item(), 'linked-set/invalid-item');
        let item_id = item.id();
        let is_duplicate = self.is_in_id_using_last(:item_id, :last_item_id);
        assert(!is_duplicate, 'linked-set/already-in-set');
        self.entry(last_item_id).write(item);
        item_id
    }

    fn add_items(self: StorageBase<Mutable<LinkedSet<T>>>, mut items_to_add: Span<T>, mut last_item_id: felt252) {
        for item in items_to_add {
            last_item_id = self.add_item_opt(item: *item, :last_item_id);
        };
    }

    fn remove_items(
        self: StorageBase<Mutable<LinkedSet<T>>>, mut items_ids_to_remove: Span<felt252>, mut last_item_id: felt252
    ) {
        for item_id in items_ids_to_remove {
            last_item_id = self.remove_opt(remove_id: *item_id, :last_item_id);
        };
    }

    fn replace_item(self: StorageBase<Mutable<LinkedSet<T>>>, item_id_to_remove: felt252, item_to_add: T) {
        let new_item_id = self.add_item(item_to_add);
        self.remove_opt(remove_id: item_id_to_remove, last_item_id: new_item_id);
    }

    fn remove(self: StorageBase<Mutable<LinkedSet<T>>>, remove_id: felt252) {
        assert(remove_id != 0, 'linked-set/invalid-id-to-remove');

        // removed pointer set to empty, Previous item set to the next item in the list
        let previous_item_id = self.item_id_before(remove_id);
        if let Option::Some(next_item) = self.next(remove_id) {
            // Removing an item in the middle
            self.entry(previous_item_id).write(next_item);
            self.entry(remove_id).write(Default::default());
        } else {
            // Removing the last item
            self.entry(previous_item_id).write(Default::default());
        }
    }

    fn remove_opt(self: StorageBase<Mutable<LinkedSet<T>>>, remove_id: felt252, last_item_id: felt252) -> felt252 {
        assert(remove_id != 0, 'linked-set/invalid-id-to-remove');

        // removed pointer set to empty, Previous item set to the next item in the list
        let previous_item_id = self.item_id_before(remove_id);
        if let Option::Some(next_item) = self.next(remove_id) {
            // Removing an item in the middle
            self.entry(previous_item_id).write(next_item);
            self.entry(remove_id).write(Default::default());
            last_item_id
        } else {
            // Removing the last item
            self.entry(previous_item_id).write(Default::default());
            previous_item_id
        }
    }
}

#[generate_trait]
impl StorageBaseAsReadOnlyImpl<T> of StorageBaseAsReadOnly<T> {
    fn as_read_only(self: StorageBase<Mutable<T>>) -> StorageBase<T> {
        StorageBase { __base_address__: self.__base_address__ }
    }
}

// Allow read operations in mutable access too
impl MutableLinkedSetReadImpl<
    T, +Drop<T>, +Store<T>, +SetItem<T>,
> of LinkedSetRead<StorageBase<Mutable<LinkedSet<T>>>> {
    type Value = T;

    fn is_empty(self: StorageBase<Mutable<LinkedSet<T>>>) -> bool {
        self.as_read_only().is_empty()
    }
    fn is_in(self: StorageBase<Mutable<LinkedSet<T>>>, item: T) -> bool {
        self.as_read_only().is_in(item)
    }

    fn is_in_id(self: StorageBase<Mutable<LinkedSet<T>>>, item_id: felt252) -> bool {
        self.as_read_only().is_in_id(item_id)
    }

    fn is_in_id_using_last(self: StorageBase<Mutable<LinkedSet<T>>>, item_id: felt252, last_item_id: felt252) -> bool {
        self.as_read_only().is_in_id_using_last(item_id, last_item_id)
    }

    fn find_last_id(self: StorageBase<Mutable<LinkedSet<T>>>) -> felt252 {
        self.as_read_only().find_last_id()
    }

    fn len(self: StorageBase<Mutable<LinkedSet<T>>>) -> usize {
        self.as_read_only().len()
    }

    fn load(self: StorageBase<Mutable<LinkedSet<T>>>) -> (usize, felt252) {
        self.as_read_only().load()
    }

    fn first(self: StorageBase<Mutable<LinkedSet<T>>>) -> Option<T> {
        self.as_read_only().first()
    }

    fn single(self: StorageBase<Mutable<LinkedSet<T>>>) -> Option<T> {
        self.as_read_only().single()
    }

    fn next(self: StorageBase<Mutable<LinkedSet<T>>>, item_id: felt252) -> Option<T> {
        self.as_read_only().next(item_id)
    }

    fn item_id_before(self: StorageBase<Mutable<LinkedSet<T>>>, item_after_id: felt252) -> felt252 {
        self.as_read_only().item_id_before(item_after_id)
    }

    fn get_all_ids(self: StorageBase<Mutable<LinkedSet<T>>>) -> Array<felt252> {
        self.as_read_only().get_all_ids()
    }
}

