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
    fn find_last_id(self: TMemberState) -> felt252;
    fn first(self: TMemberState) -> Option<Self::Value>;
    // Returns the first item if there is one item in the list, otherwise returns None
    fn single(self: TMemberState) -> Option<Self::Value>;
    fn next(self: TMemberState, item: Self::Value) -> Option<Self::Value>;
    fn item_id_before(self: TMemberState, item_after_id: felt252) -> felt252;
    fn load(self: TMemberState) -> (usize, felt252);
    fn get_all_ids(self: TMemberState) -> Array<felt252>;
}

/// Trait for reading a contract/component storage member in a specific key place.
pub trait LinkedSetWrite<TMemberState> {
    type Value;
    fn remove(self: TMemberState, remove_id: felt252);
    fn add_item(self: TMemberState, item: Self::Value);
}


impl LinkedSetReadImpl<T, +Drop<T>, +starknet::Store<T>, +SetItem<T>> of LinkedSetRead<StorageBase<LinkedSet<T>>> {
    type Value = T;

    fn is_empty(self: StorageBase<LinkedSet<T>>) -> bool {
        let first_item = self.entry(0).read();
        !first_item.is_valid_item()
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
        let next_item: T = self.entry(item_id).read();
        if next_item.is_valid_item() {
            return true;
        }
        // check if its the latest
        self.find_last_id() == item_id
    }

    // Return the last item id or zero when the list is empty. Cost increases with the list size
    fn find_last_id(self: StorageBase<LinkedSet<T>>) -> felt252 {
        let mut current_item = self.entry(0).read();
        if !current_item.is_valid_item() {
            return 0;
        }
        loop {
            let current_item_id = current_item.id();
            let next_item = self.entry(current_item_id).read();
            if !next_item.is_valid_item() {
                break current_item_id;
            }
            current_item = next_item;
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
            let next_item = self.entry(current_item_id).read();
            if !next_item.is_valid_item() {
                break (size, current_item_id);
            }
            current_item_id = next_item.id();
            size += 1;
        }
    }

    fn first(self: StorageBase<LinkedSet<T>>) -> Option<T> {
        let first_item = self.entry(0).read();
        if !first_item.is_valid_item() {
            Option::None
        } else {
            Option::Some(first_item)
        }
    }

    fn single(self: StorageBase<LinkedSet<T>>) -> Option<T> {
        let first_item = self.first()?;
        let second_item = self.entry(first_item.id()).read();
        if second_item.is_valid_item() {
            // More than one item in the list
            return Option::None;
        }
        Option::Some(first_item)
    }

    fn next(self: StorageBase<LinkedSet<T>>, item: T) -> Option<T> {
        assert(item.is_valid_item(), 'linked-set/invalid-item');
        let next_item = self.entry(item.id()).read();
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
            let next_item = self.entry(current_item_id).read();
            assert(next_item.is_valid_item(), 'linked-set/item-not-found');
            let next_item_id = next_item.id();
            if next_item_id == item_after_id {
                break current_item_id;
            }
            current_item_id = next_item_id;
        }
    }

    fn get_all_ids(self: StorageBase<LinkedSet<T>>) -> Array<felt252> {
        let mut current_item = self.entry(0).read();
        let mut ids = array![];
        loop {
            if !current_item.is_valid_item() {
                break;
            }
            let current_item_id = current_item.id();
            ids.append(current_item_id);
            current_item = self.entry(current_item_id).read();
        };
        ids
    }
}

impl LinkedSetWriteImpl<
    T, +Drop<T>, +Store<T>, +SetItem<T>, +Default<T>
> of LinkedSetWrite<StorageBase<Mutable<LinkedSet<T>>>> {
    type Value = T;

    fn add_item(self: StorageBase<Mutable<LinkedSet<T>>>, item: T) {
        assert(item.is_valid_item(), 'linked-set/invalid-item');
        let item_id = item.id();
        let is_duplicate = self.is_in_id(item_id);
        assert(!is_duplicate, 'linked-set/already-in-set');
        let last_item_id = self.find_last_id();
        self.entry(last_item_id).write(item);
    }

    fn remove(self: StorageBase<Mutable<LinkedSet<T>>>, remove_id: felt252) {
        assert(remove_id != 0, 'linked-set/invalid-id-to-remove');

        // removed set to empty, Previous item set to the next item in the list
        let previous_item_id = self.item_id_before(remove_id);
        let next_item = self.entry(remove_id).read();
        let next_item_valid = next_item.is_valid_item();
        self.entry(previous_item_id).write(next_item);
        if (next_item_valid) {
            // Removing an item in the middle
            self.entry(remove_id).write(Default::default());
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

    fn next(self: StorageBase<Mutable<LinkedSet<T>>>, item: T) -> Option<T> {
        self.as_read_only().next(item)
    }

    fn item_id_before(self: StorageBase<Mutable<LinkedSet<T>>>, item_after_id: felt252) -> felt252 {
        self.as_read_only().item_id_before(item_after_id)
    }

    fn get_all_ids(self: StorageBase<Mutable<LinkedSet<T>>>) -> Array<felt252> {
        self.as_read_only().get_all_ids()
    }
}

