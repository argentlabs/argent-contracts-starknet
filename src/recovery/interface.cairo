use argent::signer::signer_signature::{Signer, SignerSignature};
use argent::utils::array_ext::StoreFelt252Array;
use starknet::ContractAddress;

#[starknet::interface]
trait IRecovery<TContractState> {
    fn trigger_escape(ref self: TContractState, target_signers: Array<Signer>, new_signers: Array<Signer>);
    fn execute_escape(ref self: TContractState);
    fn cancel_escape(ref self: TContractState);
}

/// @notice Guardian escape was triggered by the owner
/// @param ready_at when the escape can be completed
/// @param target_signer the escaped signer address
/// @param new_signer the new signer address to be set after the security period
#[derive(Drop, starknet::Event)]
struct EscapeTriggered {
    ready_at: u64,
    target_signers: Span<felt252>,
    new_signers: Span<felt252>
}

/// @notice Signer escape was completed and there is a new signer
/// @param target_signer the escaped signer address
/// @param new_signer the new signer address
#[derive(Drop, starknet::Event)]
struct EscapeExecuted {
    target_signers: Span<felt252>,
    new_signers: Span<felt252>
}

/// @notice Signer escape was completed and there is a new signer
/// @param target_signer the escaped signer address
/// @param new_signer the new signer address
#[derive(Drop, starknet::Event)]
struct EscapeCanceled {
    target_signers: Span<felt252>,
    new_signers: Span<felt252>
}

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

// TODO can be optimised by only storing the len of the arrays once since it must be equal
#[derive(Drop, Serde, starknet::Store)]
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

const SHIFT_8: felt252 = 0x100;
const SHIFT_64: felt252 = 0x10000000000000000;

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
