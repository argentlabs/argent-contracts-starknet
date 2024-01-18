#[derive(Drop, Copy, Serde, PartialEq)]
enum EscapeStatus {
    /// No escape triggered, or it was canceled
    None,
    /// Escape was triggered and it's waiting for the `escapeSecurityPeriod`
    NotReady,
    /// The security period has elapsed and the escape is ready to be completed
    Ready,
    /// No confirmation happened for `escapeExpiryPeriod` since it became `Ready`. The escape cannot be completed now, only canceled
    Expired,
}

#[derive(Drop, Copy, Serde)]
struct Escape {
    // timestamp for activation of escape mode, 0 otherwise
    ready_at: u64,
    // None, Guardian, Owner
    escape_type: felt252,
    // new owner or new guardian address
    new_signer: felt252,
}

const SHIFT_64: felt252 = 0x10000000000000000;

// Packing ready_at and escape_type within same felt:
// bits [0; 63] => ready_at
// bits [64; ∞[ => escape_type
impl EscapeStorePacking of starknet::StorePacking<Escape, (felt252, felt252)> {
    fn pack(value: Escape) -> (felt252, felt252) {
        let packed: felt252 = value.ready_at.into() + (value.escape_type.into() * SHIFT_64);
        (packed, value.new_signer)
    }

    fn unpack(value: (felt252, felt252)) -> Escape {
        let (packed, new_signer) = value;
        let packed: u256 = packed.into();
        let shift_64: u256 = SHIFT_64.into();
        let shift_64: NonZero<u256> = shift_64.try_into().unwrap();
        let (escape_type, ready_at) = integer::u256_safe_div_rem(packed, shift_64);
        Escape { escape_type: escape_type.try_into().unwrap(), ready_at: ready_at.try_into().unwrap(), new_signer }
    }
}
