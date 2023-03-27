use serde::Serde;

use starknet::StorageAccess;

#[derive(Drop, Copy, Serde)]
struct Escape {
    active_at: u64,
    escape_type: felt252, // TODO Change to enum? ==> Can't do ATM because would have to impl partialEq, update storage, etc etc
}

impl StorageAccessEscape of StorageAccess::<Escape> {
    fn read(
        address_domain: u32, base: starknet::StorageBaseAddress
    ) -> starknet::SyscallResult<Escape> {
        Result::Ok(
            Escape {
                active_at: (StorageAccess::read(address_domain, base)?),
                escape_type: starknet::storage_read_syscall(
                    address_domain, starknet::storage_address_from_base_and_offset(base, 1_u8)
                )?,
            }
        )
    }
    fn write(
        address_domain: u32, base: starknet::StorageBaseAddress, value: Escape
    ) -> starknet::SyscallResult<()> {
        StorageAccess::write(address_domain, base, value.active_at)?;
        starknet::storage_write_syscall(
            address_domain,
            starknet::storage_address_from_base_and_offset(base, 1_u8),
            value.escape_type
        )
    }
}

