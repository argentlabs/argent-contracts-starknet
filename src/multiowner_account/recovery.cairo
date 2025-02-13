use argent::signer::signer_signature::SignerStorageValue;
use core::starknet::storage_access::StorePacking;

/// @notice Represents the type of escape in progress
#[derive(Drop, Copy, Serde, PartialEq, Default)]
pub enum EscapeType {
    #[default]
    None,
    Guardian,
    Owner,
}

/// @notice Configuration for an escape process
/// @param ready_at Timestamp when the escape can be completed
/// @param escape_type Type of escape in progress
/// @param new_signer Replacement signer for the escaped role, or None if there's no replacement
#[derive(Drop, Copy, Serde, Default)]
pub struct Escape {
    pub ready_at: u64,
    pub escape_type: EscapeType,
    pub new_signer: Option<SignerStorageValue>,
}

const SHIFT_64: felt252 = 0x10000000000000000;
const SHIFT_128: felt252 = 0x100000000000000000000000000000000;

/// @notice Packs Escape struct into two felt252 values for storage
/// felt1: [0-63] ready_at | [64-127] escape_type | [128-191] new_signer.signer_type
/// felt2: [0-251] new_signer.stored_value
impl EscapeStorePacking of StorePacking<Escape, (felt252, felt252)> {
    fn pack(value: Escape) -> (felt252, felt252) {
        let (signer_type_ordinal, stored_value) = match value.new_signer {
            Option::Some(new_signer) => (new_signer.signer_type.into(), new_signer.stored_value.into()),
            Option::None => (0, 0),
        };
        let packed = value.ready_at.into() + (value.escape_type.into() * SHIFT_64) + (signer_type_ordinal * SHIFT_128);
        (packed, stored_value)
    }

    fn unpack(value: (felt252, felt252)) -> Escape {
        let (packed, stored_value) = value;
        let shift_64: u256 = SHIFT_64.into();
        let shift_64 = shift_64.try_into().unwrap();
        let packed: u256 = packed.try_into().unwrap();
        let (remainder, ready_at) = DivRem::div_rem(packed.into(), shift_64);
        let (signer_type_ordinal, escape_type) = DivRem::div_rem(remainder, shift_64);
        Escape {
            escape_type: escape_type.try_into().unwrap(),
            ready_at: ready_at.try_into().unwrap(),
            new_signer: if signer_type_ordinal == 0 && stored_value == 0 {
                Option::None
            } else {
                let signer_type = signer_type_ordinal.try_into().unwrap();
                let stored_value = stored_value.try_into().unwrap();
                Option::Some(SignerStorageValue { signer_type, stored_value })
            },
        }
    }
}

impl EscapeTypeIntoFelt252 of Into<EscapeType, felt252> {
    fn into(self: EscapeType) -> felt252 {
        match self {
            EscapeType::None => 0,
            EscapeType::Guardian => 1,
            EscapeType::Owner => 2,
        }
    }
}

impl U256TryIntoEscapeType of TryInto<u256, EscapeType> {
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
