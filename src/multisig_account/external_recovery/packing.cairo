use argent::multisig_account::external_recovery::interface::EscapeEnabled;
use core::num::traits::zero::Zero;
use starknet::storage_access::StorePacking;

const SHIFT_8: felt252 = 0x100;
const SHIFT_64: felt252 = 0x10000000000000000;

pub impl PackEscapeEnabled of StorePacking<EscapeEnabled, felt252> {
    fn pack(value: EscapeEnabled) -> felt252 {
        (value.is_enabled.into()
            + value.security_period.into() * SHIFT_8
            + value.expiry_period.into() * SHIFT_8 * SHIFT_64)
    }

    fn unpack(value: felt252) -> EscapeEnabled {
        let value: u256 = value.into();
        let shift_8: u256 = SHIFT_8.into();
        let shift_8: NonZero<u256> = shift_8.try_into().unwrap();
        let shift_64: u256 = SHIFT_64.into();
        let shift_64: NonZero<u256> = shift_64.try_into().unwrap();
        let (rest, is_enabled) = DivRem::div_rem(value, shift_8);
        let (expiry_period, security_period) = DivRem::div_rem(rest, shift_64);

        EscapeEnabled {
            is_enabled: !is_enabled.is_zero(),
            security_period: security_period.try_into().unwrap(),
            expiry_period: expiry_period.try_into().unwrap(),
        }
    }
}
