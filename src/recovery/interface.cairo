use argent::signer::signer_signature::{Signer, SignerStorageValue, SignerSignature, SignerType};
use argent::utils::array_ext::StoreFelt252Array;
use core::array::ArrayTrait;
use core::array::SpanTrait;
use core::option::OptionTrait;
use core::traits::TryInto;
use starknet::ContractAddress;

#[starknet::interface]
trait IRecovery<TContractState> {
    fn trigger_escape(ref self: TContractState, target_signers: Array<Signer>, new_signers: Array<Signer>);
    fn execute_escape(ref self: TContractState);
    fn cancel_escape(ref self: TContractState);
    fn get_escape_enabled(self: @TContractState) -> EscapeEnabled;
    fn get_escape(self: @TContractState) -> (Escape, EscapeStatus);
}

/// @notice Escape was triggered
/// @param ready_at when the escape can be completed
/// @param target_signers the signers to escape
/// @param new_signers the new signers to be set after the security period
#[derive(Drop, starknet::Event)]
struct EscapeTriggered {
    ready_at: u64,
    target_signers: Span<felt252>,
    new_signers: Span<felt252>
}

/// @notice Signer escape was completed and there is a new signer
/// @param target_signers the signers to escape
/// @param new_signers the new signers to be set after the security period
#[derive(Drop, starknet::Event)]
struct EscapeExecuted {
    target_signers: Span<felt252>,
    new_signers: Span<felt252>
}

/// @notice Signer escape was completed and there is a new signer
/// @param target_signers the signers to escape
/// @param new_signers the new signers to be set after the security period
#[derive(Drop, starknet::Event)]
struct EscapeCanceled {
    target_signers: Span<felt252>,
    new_signers: Span<felt252>
}

#[derive(Drop, Copy, Serde, PartialEq, Debug)]
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

#[derive(Drop, Serde, starknet::StorePacking)]
struct Escape {
    // timestamp for activation of escape mode, 0 otherwise
    ready_at: u64,
    // target signer address
    target_signers: Array<felt252>,
    // new signer address
    new_signers: Array<felt252>,
}

#[derive(Drop, Copy, Serde, starknet::StorePacking)]
struct EscapeEnabled {
    // The escape is enabled
    is_enabled: u8,
    // Time it takes for the escape to become ready after being triggered
    security_period: u64,
    //  The escape will be ready and can be completed for this duration
    expiry_period: u64,
}

#[derive(Drop, Copy, Serde, PartialEq, Default)]
enum LegacyEscapeType {
    #[default]
    None,
    Guardian,
    Owner
}

#[derive(Drop, Copy, Serde, Default)]
struct LegacyEscape {
    // timestamp for activation of escape mode, 0 otherwise
    ready_at: u64,
    // None, Guardian, Owner
    escape_type: LegacyEscapeType,
    // new owner or new guardian address
    new_signer: Option<SignerStorageValue>,
}

const SHIFT_8: felt252 = 0x100;
const SHIFT_64: felt252 = 0x10000000000000000;
const SHIFT_128: felt252 = consteval_int!(0x10000000000000000 * 0x10000000000000000);

impl PackEscapeEnabled of starknet::StorePacking<EscapeEnabled, felt252> {
    fn pack(value: EscapeEnabled) -> felt252 {
        (value.is_enabled.into()
            + value.security_period.into() * SHIFT_8
            + value.expiry_period.into() * SHIFT_8 * SHIFT_64)
    }

    fn unpack(value: felt252) -> EscapeEnabled {
        let value: u256 = value.into();
        let shift_8: NonZero<u256> = integer::u256_try_as_non_zero(SHIFT_8.into()).unwrap();
        let shift_64: NonZero<u256> = integer::u256_try_as_non_zero(SHIFT_64.into()).unwrap();
        let (rest, is_enabled) = integer::u256_safe_div_rem(value, shift_8);
        let (expiry_period, security_period) = integer::u256_safe_div_rem(rest, shift_64);

        EscapeEnabled {
            is_enabled: is_enabled.try_into().unwrap(),
            security_period: security_period.try_into().unwrap(),
            expiry_period: expiry_period.try_into().unwrap(),
        }
    }
}

impl PackEscape of starknet::StorePacking<Escape, Array<felt252>> {
    fn pack(value: Escape) -> Array<felt252> {
        let mut arr: Array<felt252> = array![];
        arr.append(value.ready_at.into());
        let mut target_signers_span = value.target_signers.span();
        let mut new_signers_span = value.new_signers.span();
        assert(target_signers_span.len() == new_signers_span.len(), 'argent/invalid-len');
        loop {
            let target_signer = match target_signers_span.pop_front() {
                Option::Some(target_signer) => (*target_signer),
                Option::None => { break; }
            };
            arr.append(target_signer);
            arr.append(*new_signers_span.pop_front().expect('argent/invalid-array-len'));
        };
        arr
    }

    fn unpack(value: Array<felt252>) -> Escape {
        if value.is_empty() {
            Escape { ready_at: 0, target_signers: array![], new_signers: array![] }
        } else {
            let mut target_signers = array![];
            let mut new_signers = array![];

            let mut value_span = value.span();
            let ready_at = *value_span.pop_front().unwrap();
            loop {
                let target_signer = value_span.pop_front();
                let new_signer = match value_span.pop_front() {
                    Option::Some(item) => *item,
                    Option::None => { break; }
                };
                target_signers.append(*target_signer.unwrap());
                new_signers.append(new_signer);
            };
            Escape { ready_at: ready_at.try_into().unwrap(), target_signers: target_signers, new_signers: new_signers }
        }
    }
}

// Packing ready_at, escape_type and new_signer.signer_type within same felt:
// felt1 bits [0; 63] => ready_at
// felt1 bits [64; 127] => escape_type
// felt1 bits [128; 191] => new_signer.signer_type
// felt2 bits [0; 251] => new_signer.stored_value
impl LegacyEscapeStorePacking of starknet::StorePacking<LegacyEscape, (felt252, felt252)> {
    fn pack(value: LegacyEscape) -> (felt252, felt252) {
        let (signer_type_ordinal, stored_value) = match value.new_signer {
            Option::Some(new_signer) => (new_signer.signer_type.into(), new_signer.stored_value.into()),
            Option::None => (0, 0)
        };
        let packed = value.ready_at.into() + (value.escape_type.into() * SHIFT_64) + (signer_type_ordinal * SHIFT_128);
        (packed, stored_value)
    }

    fn unpack(value: (felt252, felt252)) -> LegacyEscape {
        let (packed, stored_value) = value;
        let shift_64 = integer::u256_as_non_zero(SHIFT_64.into());
        let (remainder, ready_at) = integer::u256_safe_div_rem(packed.into(), shift_64);
        let (signer_type_ordinal, escape_type) = integer::u256_safe_div_rem(remainder, shift_64);
        LegacyEscape {
            escape_type: escape_type.try_into().unwrap(),
            ready_at: ready_at.try_into().unwrap(),
            new_signer: if (signer_type_ordinal == 0 && stored_value == 0) {
                Option::None
            } else {
                Option::Some(
                    SignerStorageValue {
                        signer_type: signer_type_ordinal.try_into().unwrap(),
                        stored_value: stored_value.try_into().unwrap()
                    }
                )
            }
        }
    }
}

impl EscapeTypeIntoFelt252 of Into<LegacyEscapeType, felt252> {
    #[inline(always)]
    fn into(self: LegacyEscapeType) -> felt252 implicits() nopanic {
        match self {
            LegacyEscapeType::None => 0,
            LegacyEscapeType::Guardian => 1,
            LegacyEscapeType::Owner => 2
        }
    }
}

impl U256TryIntoLegacyEscapeType of TryInto<u256, LegacyEscapeType> {
    #[inline(always)]
    fn try_into(self: u256) -> Option<LegacyEscapeType> {
        if self == 0 {
            Option::Some(LegacyEscapeType::None)
        } else if self == 1 {
            Option::Some(LegacyEscapeType::Guardian)
        } else if self == 2 {
            Option::Some(LegacyEscapeType::Owner)
        } else {
            Option::None
        }
    }
}

impl OptionDefault<T> of Default<Option<T>> {
    #[inline(always)]
    fn default() -> Option<T> {
        Option::None
    }
}
