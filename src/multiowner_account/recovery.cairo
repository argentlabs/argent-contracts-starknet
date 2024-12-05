use argent::signer::signer_signature::SignerStorageValue;
use integer::u256_safe_div_rem;

/// @notice The type of the escape telling who is about to be escaped
#[derive(Drop, Copy, Serde, PartialEq, Default)]
enum EscapeType {
    #[default]
    None,
    Guardian,
    Owner
}

/// @param ready_at when the escape can be completed
/// @param escape_type The type of the escape telling who is about to be escaped
/// @param new_signer The new signer (new owner or new guardian address) or zero if guardian removed
#[derive(Drop, Copy, Serde, Default)]
struct Escape {
    ready_at: u64,
    escape_type: EscapeType,
    new_signer: Option<SignerStorageValue>,
}


const SHIFT_64: felt252 = 0x10000000000000000;
const SHIFT_128: felt252 = 0x100000000000000000000000000000000;

// Packing ready_at, escape_type and new_signer.signer_type within same felt:
// felt1 bits [0; 63] => ready_at
// felt1 bits [64; 127] => escape_type
// felt1 bits [128; 191] => new_signer.signer_type
// felt2 bits [0; 251] => new_signer.stored_value
impl EscapeStorePacking of starknet::StorePacking<Escape, (felt252, felt252)> {
    fn pack(value: Escape) -> (felt252, felt252) {
        let (signer_type_ordinal, stored_value) = match value.new_signer {
            Option::Some(new_signer) => (new_signer.signer_type.into(), new_signer.stored_value.into()),
            Option::None => (0, 0)
        };
        let packed = value.ready_at.into() + (value.escape_type.into() * SHIFT_64) + (signer_type_ordinal * SHIFT_128);
        (packed, stored_value)
    }

    fn unpack(value: (felt252, felt252)) -> Escape {
        let (packed, stored_value) = value;
        let shift_64 = integer::u256_as_non_zero(SHIFT_64.into());
        let (remainder, ready_at) = u256_safe_div_rem(packed.into(), shift_64);
        let (signer_type_ordinal, escape_type) = u256_safe_div_rem(remainder, shift_64);
        Escape {
            escape_type: escape_type.try_into().unwrap(),
            ready_at: ready_at.try_into().unwrap(),
            new_signer: if signer_type_ordinal == 0 && stored_value == 0 {
                Option::None
            } else {
                let signer_type = signer_type_ordinal.try_into().unwrap();
                let stored_value = stored_value.try_into().unwrap();
                Option::Some(SignerStorageValue { signer_type, stored_value })
            }
        }
    }
}

impl EscapeTypeIntoFelt252 of Into<EscapeType, felt252> {
    #[inline(always)]
    fn into(self: EscapeType) -> felt252 {
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
