use starknet::StorageAccess;

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

fn enum_to_num(escape_status: EscapeStatus) -> felt252 {
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
    fn eq(a: EscapeStatus, b: EscapeStatus) -> bool {
        let aa = enum_to_num(a);
        let bb = enum_to_num(b);
        aa == bb
    }
    #[inline(always)]
    fn ne(a: EscapeStatus, b: EscapeStatus) -> bool {
        !(a == b)
    }
}

#[derive(Drop, Copy, Serde)]
struct Escape {
    active_at: u64,
    escape_type: felt252, // TODO Change to enum? ==> Can't do ATM because would have to impl partialEq, update storage, etc etc
}

impl StorageAccessEscape of StorageAccess<Escape> {
    fn read(
        address_domain: u32, base: starknet::StorageBaseAddress
    ) -> starknet::SyscallResult<Escape> {
        Result::Ok(
            Escape {
                active_at: (StorageAccess::read(address_domain, base)?),
                escape_type: starknet::storage_read_syscall(
                    address_domain, starknet::storage_address_from_base_and_offset(base, 1)
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
            starknet::storage_address_from_base_and_offset(base, 1),
            value.escape_type
        )
    }
}

