use starknet::{get_contract_address, get_caller_address, ContractAddress, account::Call};

#[inline(always)]
fn assert_only_self() {
    assert(get_contract_address() == get_caller_address(), 'argent/only-self');
}

#[inline(always)]
fn assert_only_protocol() {
    assert(get_caller_address().is_zero(), 'argent/non-null-caller');
}

fn assert_no_self_call(mut calls: Span::<Call>, self: ContractAddress) {
    loop {
        match calls.pop_front() {
            Option::Some(call) => assert(*call.to != self, 'argent/no-multicall-to-self'),
            Option::None => { break; },
        }
    }
}
