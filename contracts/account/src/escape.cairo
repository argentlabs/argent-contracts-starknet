use starknet::StorageAccess;
use starknet::StorageBaseAddress;
use starknet::SyscallResult;
use starknet::storage_read_syscall;
use starknet::storage_write_syscall;
use starknet::storage_address_from_base_and_offset;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;

#[derive(Drop, Copy)]
enum EscapeStatus {
    /// No escape triggered, or it was canceled
    None: (),
    /// Escape was triggered and it's waiting for the `escapeSecurityPeriod`
    NotReady: (),
    /// The security period has elapsed and the escape is ready to be completed
    Ready: (),
    /// No confirmation happened for `escapeExpiryPeriod` since it became `Ready`. The escape cannot be completed now, only canceled
    Expired: ()
}

fn escape_status_to_num(escape_status: EscapeStatus) -> felt252 {
    match escape_status {
        EscapeStatus::None(()) => 1,
        EscapeStatus::NotReady(()) => 2,
        EscapeStatus::Ready(()) => 3,
        EscapeStatus::Expired(()) => 4,
    }
}

// can be deleted once partialEq can be successfully derived
impl EscapeStatusPartialEq of PartialEq<EscapeStatus> {
    #[inline(always)]
    fn eq(self: EscapeStatus, other: EscapeStatus) -> bool {
        let a = escape_status_to_num(self);
        let b = escape_status_to_num(other);
        a == b
    }
    #[inline(always)]
    fn ne(self: EscapeStatus, other: EscapeStatus) -> bool {
        !(self == other)
    }
}

#[derive(Drop, Copy, Serde)]
struct Escape {
    // timestamp for activation of escape mode, 0 otherwise
    active_at: u64,
    // None, Guardian, Owner
    escape_type: felt252, // TODO Change to enum? ==> Can't do ATM because would have to impl partialEq, update storage, etc etc
    // new owner or new guardian address
    new_signer: felt252,
}

impl StorageAccessEscape of StorageAccess<Escape> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Escape> {
        Result::Ok(
            Escape {
                active_at: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 0)
                )?.try_into().unwrap(),
                escape_type: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 1)
                )?,
                new_signer: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 2)
                )?,
            }
        )
    }
    fn write(address_domain: u32, base: StorageBaseAddress, value: Escape) -> SyscallResult<()> {
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 0), value.active_at.into()
        )?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1), value.escape_type
        )?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2), value.new_signer
        )
    }
}
