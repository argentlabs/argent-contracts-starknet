/// @dev 🚨 Attention: This file has not undergone an audit and is not intended for production use. Use at your own risk. Please exercise caution and conduct your own due diligence before interacting with this contract. 🚨
use starknet::{SyscallResult, storage_access::{Store, StorageBaseAddress}};

// Can store up to 255 felt252
impl StoreFelt252Array of Store<Array<felt252>> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Array<felt252>> {
        Self::read_at_offset(address_domain, base, 0)
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: Array<felt252>) -> SyscallResult<()> {
        Self::write_at_offset(address_domain, base, 0, value)
    }

    fn read_at_offset(address_domain: u32, base: StorageBaseAddress, mut offset: u8) -> SyscallResult<Array<felt252>> {
        let mut arr: Array<felt252> = ArrayTrait::new();

        // Read the stored array's length. If the length is superior to 255, the read will fail.
        let len: u8 = Store::<u8>::read_at_offset(address_domain, base, offset).expect('argent/array-too-large');
        offset += 1;

        // Sequentially read all stored elements and append them to the array.
        let exit = len + offset;
        while offset < exit {
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
        // Store the length of the array in the first storage slot.
        let len: u8 = value.len().try_into().expect('argent/array-too-large');
        Store::<u8>::write_at_offset(address_domain, base, offset, len).expect('argent/unwritable');
        offset += 1;

        // Store the array elements sequentially
        while let Option::Some(element) = value
            .pop_front() {
                Store::<felt252>::write_at_offset(address_domain, base, offset, element).unwrap();
                offset += Store::<felt252>::size();
            };
        Result::Ok(())
    }

    fn size() -> u8 {
        255 * Store::<felt252>::size()
    }
}

