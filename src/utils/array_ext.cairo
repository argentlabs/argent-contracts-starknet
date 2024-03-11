use array::ArrayTrait;

use starknet::{SyscallResult, storage_access::{Store, StorageBaseAddress}};
trait ArrayExtTrait<T> {
    fn append_all(ref self: Array<T>, value: Array<T>);
}

impl ArrayExtImpl<T, +Drop<T>> of ArrayExtTrait<T> {
    fn append_all(ref self: Array<T>, mut value: Array<T>) {
        loop {
            match value.pop_front() {
                Option::Some(item) => self.append(item),
                Option::None => { break; },
            }
        }
    }
}

// Can store up to 255 felt252
impl StoreFelt252Array of Store<Array<felt252>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Array<felt252>> {
        StoreFelt252Array::read_at_offset(address_domain, base, 0)
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Array<felt252>) -> SyscallResult<()> {
        StoreFelt252Array::write_at_offset(address_domain, base, 0, value)
    }

    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, mut offset: u8) -> SyscallResult<Array<felt252>> {
        let mut arr: Array<felt252> = ArrayTrait::new();

        // Read the stored array's length. If the length is superior to 255, the read will fail.
        let len: u8 = Store::<u8>::read_at_offset(address_domain, base, offset).expect('argent/array-too-large');
        offset += 1;

        // Sequentially read all stored elements and append them to the array.
        let exit = len + offset;
        loop {
            if offset >= exit {
                break;
            }

            let value = Store::<felt252>::read_at_offset(address_domain, base, offset).unwrap();
            arr.append(value);
            offset += Store::<felt252>::size();
        };

        // Return the array.
        Result::Ok(arr)
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, mut offset: u8, mut value: Array<felt252>
    ) -> SyscallResult<()> {
        // // Store the length of the array in the first storage slot.
        let len: u8 = value.len().try_into().expect('argent/array-too-large');
        Store::<u8>::write_at_offset(address_domain, base, offset, len).expect('argent/unwritable');
        offset += 1;

        // Store the array elements sequentially
        loop {
            match value.pop_front() {
                Option::Some(element) => {
                    Store::<felt252>::write_at_offset(address_domain, base, offset, element).unwrap();
                    offset += Store::<felt252>::size();
                },
                Option::None(_) => { break Result::Ok(()); }
            };
        }
    }

    fn size() -> u8 {
        255 * Store::<felt252>::size()
    }
}

