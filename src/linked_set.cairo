use argent::signer::{
    signer_signature::{Signer, SignerTrait, SignerSignature, SignerStorageValue, SignerSignatureTrait, SignerSpanTrait},
};
use starknet::Store;
use starknet::storage::StoragePathEntry;
use starknet::storage::{
    StorageAsPath, StorageAsPointer, StoragePath, StoragePointer0Offset, Mutable, StoragePathTrait,
    StoragePathUpdateTrait, StoragePointerReadAccess, StoragePointerWriteAccess, StorageBase, Map
};

trait SetItem<T> {
    // TODO rename? this is needed mostly to check if the result of reading storage is valid, but also to ensure we
    // don't store invalid itens
    fn is_valid_item(self: @T) -> bool;
    // can't be zero unless it's an invalid item, actually it should never be called on an invalid item, maybe can
    // return NonZero<felt252>? also add a nothe that the ids must be unique
    fn id(self: @T) -> felt252;
}

#[derive(Drop, Copy)]
pub struct LinkedSet<T> {
    pub storage: StorageBase<Map<felt252, T>>,
}

#[derive(Drop, Copy)]
pub struct LinkedSetMut<T> {
    pub storage: StorageBase<Mutable<Map<felt252, T>>>,
}

pub trait LinkedSetTrait<T> {
    fn len(self: LinkedSet<T>) -> usize;
    fn is_empty(self: LinkedSet<T>) -> bool;
    fn is_in(self: LinkedSet<T>, item: T) -> bool;
    fn is_in_id(self: LinkedSet<T>, item_id: felt252) -> bool;
    fn find_last_id(self: LinkedSet<T>) -> felt252;
    fn first(self: LinkedSet<T>) -> Option<T>;
    fn next(self: LinkedSet<T>, item: T) -> Option<T>;
    fn item_id_before(self: LinkedSet<T>, item_after_id: felt252) -> felt252;
    fn load(self: LinkedSet<T>) -> (usize, felt252);
    fn get_all_ids(self: LinkedSet<T>) -> Array<felt252>;
}

pub trait LinkedSetTraitMut<T> {
    fn read(self: @LinkedSetMut<T>) -> LinkedSet<T>;
    fn remove(self: LinkedSetMut<T>, remove_id: felt252);
    fn add_item(self: LinkedSetMut<T>, item: T);
}

pub impl LinkedSetImpl<T, +SetItem<T>, +Store<T>, +Copy<T>, +Drop<T>> of LinkedSetTrait<T> {
    fn is_empty(self: LinkedSet<T>) -> bool {
        let first_item = self.storage.entry(0).read();
        !first_item.is_valid_item()
    }

    fn is_in(self: LinkedSet<T>, item: T) -> bool {
        if !item.is_valid_item() {
            return false;
        }
        self.is_in_id(item.id())
    }

    fn is_in_id(self: LinkedSet<T>, item_id: felt252) -> bool {
        if item_id == 0 {
            return false;
        }
        let next_item: T = self.storage.entry(item_id).read();
        if next_item.is_valid_item() {
            return true;
        }
        // check if its the latest
        self.find_last_id() == item_id
    }

    // Return the last item id or zero when the list is empty. Cost increases with the list size
    fn find_last_id(self: LinkedSet<T>) -> felt252 {
        let mut current_item = self.storage.entry(0).read();
        if !current_item.is_valid_item() {
            return 0;
        }
        loop {
            let current_item_id = current_item.id();
            let next_item = self.storage.entry(current_item_id).read();
            if !next_item.is_valid_item() {
                break current_item_id;
            }
            current_item = next_item;
        }
    }

    fn len(self: LinkedSet<T>) -> usize {
        let (len, _) = self.load();
        len
    }

    // Returns the number of signers and the last item id (or zero if the list is empty). Cost
    // increases with the list size
    /// returns (len, last_item_id)
    fn load(self: LinkedSet<T>) -> (usize, felt252) {
        let mut current_item_id = 0;
        let mut size = 0;
        loop {
            let next_item = self.storage.entry(current_item_id).read();
            if !next_item.is_valid_item() {
                break (size, current_item_id);
            }
            current_item_id = next_item.id();
            size += 1;
        }
    }

    fn first(self: LinkedSet<T>) -> Option<T> {
        let first_item = self.storage.entry(0).read();
        if !first_item.is_valid_item() {
            Option::None
        } else {
            Option::Some(first_item)
        }
    }

    fn next(self: LinkedSet<T>, item: T) -> Option<T> {
        assert(item.is_valid_item(), 'linked-set/invalid-item');
        let next_item = self.storage.entry(item.id()).read();
        if !next_item.is_valid_item() {
            Option::None
        } else {
            Option::Some(next_item)
        }
    }

    fn item_id_before(self: LinkedSet<T>, item_after_id: felt252) -> felt252 {
        assert(item_after_id != 0, 'linked-set/item-after-id');
        let mut current_item_id = 0;
        loop {
            let next_item = self.storage.entry(current_item_id).read();
            assert(next_item.is_valid_item(), 'linked-set/item-not-found');
            let next_item_id = next_item.id();
            if next_item_id == item_after_id {
                break current_item_id;
            }
            current_item_id = next_item_id;
        }
    }

    fn get_all_ids(self: LinkedSet<T>) -> Array<felt252> {
        let mut current_item = self.storage.entry(0).read();
        let mut ids = array![];
        loop {
            if !current_item.is_valid_item() {
                break;
            }
            let current_item_id = current_item.id();
            ids.append(current_item_id);
            current_item = self.storage.entry(current_item_id).read();
        };
        ids
    }
}

pub impl LinkedSetMutImpl<T, +SetItem<T>, +Store<T>, +Copy<T>, +Drop<T>, +Default<T>> of LinkedSetTraitMut<T> {
    fn read(self: @LinkedSetMut<T>) -> LinkedSet<T> {
        LinkedSet { storage: StorageBase { __base_address__: *self.storage.__base_address__ } }
    }

    fn add_item(self: LinkedSetMut<T>, item: T) {
        assert(item.is_valid_item(), 'linked-set/invalid-item');
        let item_id = item.id();
        let is_duplicate = self.read().is_in_id(item_id);
        assert(!is_duplicate, 'linked-set/already-in-set');
        let last_item_id = self.read().find_last_id();
        self.storage.entry(last_item_id).write(item);
    }

    fn remove(self: LinkedSetMut<T>, remove_id: felt252) {
        assert(remove_id != 0, 'linked-set/invalid-id-to-remove');

        // removed set to empty, Previous item set to the next item in the list
        let previous_item_id = self.read().item_id_before(remove_id);
        let next_item = self.storage.entry(remove_id).read();

        self.storage.entry(previous_item_id).write(next_item);
        if (next_item.is_valid_item()) {
            // Removing an item in the middle
            self.storage.entry(remove_id).write(Default::default());
        }
    }
}
