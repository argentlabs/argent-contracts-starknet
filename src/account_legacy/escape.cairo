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

#[derive(Drop, Copy, Serde, PartialEq, Default)]
enum EscapeType {
    #[default]
    None,
    Guardian,
    Owner
}

#[derive(Drop, Copy, Serde, Default)]
struct Escape {
    // timestamp for activation of escape mode, 0 otherwise
    ready_at: u64,
    // None, Guardian, Owner
    escape_type: EscapeType,
    // new owner or new guardian address
    new_signer: felt252,
}

const SHIFT_64: felt252 = 0x10000000000000000;

// Packing ready_at and escape_type within same felt:
// felt1 bits [0; 63] => ready_at
// felt1 bits [64; 251] => escape_type
// felt2 bits [0; 251] => new_signer
impl EscapeStorePacking of starknet::StorePacking<Escape, (felt252, felt252)> {
    fn pack(value: Escape) -> (felt252, felt252) {
        let packed = value.ready_at.into() + (value.escape_type.into() * SHIFT_64);
        (packed, value.new_signer)
    }

    fn unpack(value: (felt252, felt252)) -> Escape {
        let (packed, new_signer) = value;
        let shift_64 = integer::u256_as_non_zero(SHIFT_64.into());
        let (escape_type, ready_at) = integer::u256_safe_div_rem(packed.into(), shift_64);
        Escape { escape_type: escape_type.try_into().unwrap(), ready_at: ready_at.try_into().unwrap(), new_signer }
    }
}

impl EscapeTypeIntoFelt252 of Into<EscapeType, felt252> {
    #[inline(always)]
    fn into(self: EscapeType) -> felt252 implicits() nopanic {
        match self {
            EscapeType::None => 0,
            EscapeType::Guardian => 1,
            EscapeType::Owner => 2
        }
    }
}

impl U256TryIntoEscapeType of TryInto<u256, EscapeType> {
    #[inline(always)]
    fn try_into(self: u256) -> Option<EscapeType> {
        if self == 0 {
            Option::Some(EscapeType::None)
        } else if self == 1 {
            Option::Some(EscapeType::Guardian)
        } else if self == 2 {
            Option::Some(EscapeType::Owner)
        } else {
            Option::None
        }
    }
}
