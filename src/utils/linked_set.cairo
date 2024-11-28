use starknet::Store;
use starknet::storage::{
    StorageAsPath, StoragePathEntry, StoragePath, Mutable, StoragePathUpdateTrait, StorageBase, StoragePathTrait
};

pub trait LinkedSetConfig<T> {
    const END_MARKER: T;

    fn is_valid_item(self: @T) -> bool;

    // returns a unique id for the given item. The id can't be zero as it's reserved for the first item
    // TODO explain it cant return ids like 1,2,3 if the actual storage size is more than 1 felt252 because the is is
    // actually the offset in the storage
    fn id(self: @T) -> felt252;

    // must return valid items
    // reads the value stored at the given path or empty if there is no valid value
    fn path_read_value(path: StoragePath<T>) -> Option<T>;

    // checks if the value stored in the given path is valid or the end marker
    fn path_is_in_set(path: StoragePath<T>) -> bool;
}

#[phantom]
pub struct LinkedSet<T> {}

pub trait LinkedSetRead<TMemberState> {
    type Value;
    fn len(self: TMemberState) -> usize;
    fn is_empty(self: TMemberState) -> bool;
    fn is_in(self: TMemberState, item_id: felt252) -> bool;
    fn first(self: TMemberState) -> Option<Self::Value>;
    fn get_all_ids(self: TMemberState) -> Array<felt252>;
}

pub trait LinkedSetWrite<TMemberState> {
    type Value;
    /// @returns the id of the inserted item which is now the latest item on the list
    fn add_item(self: TMemberState, item: Self::Value) -> felt252;
    fn add_items(self: TMemberState, items_to_add: Span<Self::Value>);
    fn remove(self: TMemberState, remove_id: felt252);
    fn remove_items(self: TMemberState, items_ids_to_remove: Span<felt252>);

    /// @notice Replace one item with a different one
    /// @dev Will revert when trying to remove an item that isn't in the list
    /// @dev Will revert when trying to add an item that is in the list or if the item is invalid
    /// @dev Will revert if both items are the same
    /// @param item_id_to_remove Id of the item to remove
    /// @param item_to_add Item to add
    fn replace_item(self: TMemberState, item_id_to_remove: felt252, item_to_add: Self::Value);
}

impl LinkedSetReadImpl<
    T, +Drop<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>
> of LinkedSetRead<StorageBase<LinkedSet<T>>> {
    type Value = T;

    fn is_empty(self: StorageBase<LinkedSet<T>>) -> bool {
        self.first().is_none()
    }

    #[inline(always)]
    fn is_in(self: StorageBase<LinkedSet<T>>, item_id: felt252) -> bool {
        if item_id == 0 {
            return false;
        }
        LinkedSetConfig::path_is_in_set(path: self.entry(item_id))
    }

    fn len(self: StorageBase<LinkedSet<T>>) -> usize {
        let mut current_item_id = 0;
        let mut size = 0;
        loop {
            if let Option::Some(next_item) = self.next(current_item_id) {
                current_item_id = next_item.id();
                size += 1;
            } else {
                break size;
            }
        }
    }

    fn first(self: StorageBase<LinkedSet<T>>) -> Option<T> {
        self.next(0)
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

#[generate_trait]
impl LinkedSetReadPrivateImpl<T, +Drop<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>> of LinkedSetReadPrivate<T> {
    #[inline(always)]
    fn entry(self: StorageBase<LinkedSet<T>>, entry_id: felt252) -> StoragePath<T> {
        let path: StoragePath<T> = StoragePathTrait::new(self.as_path().__hash_state__.state);
        path.update(entry_id)
    }

    #[inline(always)]
    fn next(self: StorageBase<LinkedSet<T>>, item_id: felt252) -> Option<T> {
        LinkedSetConfig::path_read_value(path: self.entry(item_id))
    }

    // Return the last item id or zero when the list is empty. Cost increases with the list size
    #[inline(always)]
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
}

impl LinkedSetWriteImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>
> of LinkedSetWrite<StorageBase<Mutable<LinkedSet<T>>>> {
    type Value = T;

    #[inline(always)]
    fn add_item(self: StorageBase<Mutable<LinkedSet<T>>>, item: T) -> felt252 {
        self.add_item_opt(:item, last_item_id: self.find_last_id())
    }

    #[inline(always)]
    fn add_items(self: StorageBase<Mutable<LinkedSet<T>>>, mut items_to_add: Span<T>) {
        let mut last_item_id: felt252 = self.find_last_id();
        for item in items_to_add {
            last_item_id = self.add_item_opt(item: *item, :last_item_id);
        };
    }

    fn remove_items(self: StorageBase<Mutable<LinkedSet<T>>>, mut items_ids_to_remove: Span<felt252>) {
        for item_id in items_ids_to_remove {
            self.remove(remove_id: *item_id);
        };
    }

    fn replace_item(self: StorageBase<Mutable<LinkedSet<T>>>, item_id_to_remove: felt252, item_to_add: T) {
        self.add_item(item_to_add);
        self.remove(remove_id: item_id_to_remove);
    }

    fn remove(self: StorageBase<Mutable<LinkedSet<T>>>, remove_id: felt252) {
        assert(remove_id != 0, 'linked-set/invalid-id-to-remove');

        // Previous item set to the next item in the list
        let previous_item_id = self.item_id_before(remove_id);

        if let Option::Some(next_item) = self.next(remove_id) {
            // Removing an item in the middle
            self.entry(previous_item_id).write(next_item);
        } else {
            // Removing the last item
            self.entry(previous_item_id).write(LinkedSetConfig::END_MARKER);
        }
        // removed pointer set to empty
        self.entry(remove_id).write(Default::default());
    }
}
#[generate_trait]
impl LinkedSetWritePrivateImpl<
    T, +Drop<T>, +PartialEq<T>, +Copy<T>, +Store<T>, +LinkedSetConfig<T>, +Default<T>
> of LinkedSetPlus1WritePrivate<T> {
    #[inline(always)]
    fn entry(self: StorageBase<Mutable<LinkedSet<T>>>, entry_id: felt252) -> StoragePath<Mutable<T>> {
        let path: StoragePath<Mutable<T>> = StoragePathTrait::new(self.as_path().__hash_state__.state);
        path.update(entry_id)
    }

    #[inline(always)]
    fn add_item_opt(self: StorageBase<Mutable<LinkedSet<T>>>, item: T, last_item_id: felt252) -> felt252 {
        assert(item.is_valid_item(), 'linked-set/invalid-item');
        let item_id = item.id();
        let is_duplicate = self.is_in(:item_id);
        assert(!is_duplicate, 'linked-set/already-in-set');
        self.entry(last_item_id).write(item);
        self.entry(item_id).write(LinkedSetConfig::END_MARKER);
        item_id
    }

    // Allow easy access to the read-only version of the storage
    #[inline(always)]
    fn item_id_before(self: StorageBase<Mutable<LinkedSet<T>>>, item_after_id: felt252) -> felt252 {
        self.as_read_only().item_id_before(item_after_id)
    }

    #[inline(always)]
    fn next(self: StorageBase<Mutable<LinkedSet<T>>>, item_id: felt252) -> Option<T> {
        self.as_read_only().next(item_id)
    }

    #[inline(always)]
    fn find_last_id(self: StorageBase<Mutable<LinkedSet<T>>>) -> felt252 {
        self.as_read_only().find_last_id()
    }
}

#[generate_trait]
impl StorageBaseAsReadOnlyImpl<T> of StorageBaseAsReadOnly<T> {
    #[inline(always)]
    fn as_read_only(self: StorageBase<Mutable<T>>) -> StorageBase<T> {
        StorageBase { __base_address__: self.__base_address__ }
    }
}

// Allow read operations in mutable access too
impl MutableLinkedSetReadImpl<
    T, +Drop<T>, +PartialEq<T>, +Store<T>, +LinkedSetConfig<T>,
> of LinkedSetRead<StorageBase<Mutable<LinkedSet<T>>>> {
    type Value = T;

    #[inline(always)]
    fn is_empty(self: StorageBase<Mutable<LinkedSet<T>>>) -> bool {
        self.as_read_only().is_empty()
    }

    #[inline(always)]
    fn is_in(self: StorageBase<Mutable<LinkedSet<T>>>, item_id: felt252) -> bool {
        self.as_read_only().is_in(:item_id)
    }

    #[inline(always)]
    fn len(self: StorageBase<Mutable<LinkedSet<T>>>) -> usize {
        self.as_read_only().len()
    }

    #[inline(always)]
    fn first(self: StorageBase<Mutable<LinkedSet<T>>>) -> Option<T> {
        self.as_read_only().first()
    }

    #[inline(always)]
    fn get_all_ids(self: StorageBase<Mutable<LinkedSet<T>>>) -> Array<felt252> {
        self.as_read_only().get_all_ids()
    }
}
