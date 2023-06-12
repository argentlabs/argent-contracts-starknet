use starknet::{
    StorageAccess, StorageBaseAddress, SyscallResult, storage_read_syscall, storage_write_syscall,
    storage_address_from_base_and_offset
};
use traits::{Into, TryInto};
use option::{Option, OptionTrait};
use serde::Serde;
use array::{ArrayTrait, SpanTrait};

#[derive(Drop, Copy, Serde, PartialEq)]
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

#[derive(Drop, Copy, Serde, storage_access::StorageAccess)]
struct Escape {
    // timestamp for activation of escape mode, 0 otherwise
    ready_at: u64,
    // None, Guardian, Owner
    escape_type: felt252,
    // new owner or new guardian address
    new_signer: felt252,
}
