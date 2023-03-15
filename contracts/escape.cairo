use serde::Serde;

use starknet::StorageAccess;

#[derive(Drop, Copy)]
struct Escape {
    active_at: u64,
    escape_type: felt252, // TODO Change to enum? ==> Can't do ATM because would have to impl partialEq, update storage, etc etc
}

impl StorageAccessEscape of StorageAccess::<Escape> {
    fn read(
        address_domain: felt252, base: starknet::StorageBaseAddress
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
        address_domain: felt252, base: starknet::StorageBaseAddress, value: Escape
    ) -> starknet::SyscallResult<()> {
        StorageAccess::write(address_domain, base, value.active_at)?;
        starknet::storage_write_syscall(
            address_domain,
            starknet::storage_address_from_base_and_offset(base, 1_u8),
            value.escape_type
        )
    }
}

impl EscapeSerde of Serde::<Escape> {
    fn serialize(ref serialized: Array<felt252>, input: Escape) {
        Serde::serialize(ref serialized, input.active_at);
        Serde::serialize(ref serialized, input.escape_type);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<Escape> {
        Option::Some(
            Escape {
                active_at: Serde::deserialize(ref serialized)?,
                escape_type: Serde::deserialize(ref serialized)?,
            }
        )
    }
}
