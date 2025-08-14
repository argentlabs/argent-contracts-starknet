use core::num::traits::Zero;
use starknet::{ContractAddress, account::Call, get_caller_address, get_contract_address};

#[inline(always)]
pub fn assert_only_self() {
    assert(get_contract_address() == get_caller_address(), 'argent/only-self');
}

#[inline(always)]
pub fn assert_only_protocol(caller_address: ContractAddress) {
    assert(caller_address.is_zero(), 'argent/non-null-caller');
}

pub fn assert_no_self_call(calls: Span<Call>, self: ContractAddress) {
    for call in calls {
        assert(*call.to != self, 'argent/no-multicall-to-self')
    }
}
