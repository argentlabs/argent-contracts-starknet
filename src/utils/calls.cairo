use argent::utils::array_ext::ArrayExtTrait;
use starknet::{account::Call, syscalls::call_contract_syscall};

#[inline(always)]
pub fn execute_call(call: @Call, ref index: felt252) -> Span<felt252> {
    match call_contract_syscall(*call.to, *call.selector, *call.calldata) {
        Result::Ok(retdata) => {
            index += 1;
            return retdata;
        },
        Result::Err(revert_reason) => {
            let mut data = array!['argent/multicall-failed', index];
            data.append_all(revert_reason.span());
            panic(data)
        },
    }
}

pub fn execute_multicall(calls: Span<Call>) {
    let mut index = 0;
    for call in calls {
        execute_call(call, ref index);
    };
}

pub fn execute_multicall_with_result(calls: Span<Call>) -> Array<Span<felt252>> {
    let mut result = array![];
    let mut index = 0;
    for call in calls {
        match call_contract_syscall(*call.to, *call.selector, *call.calldata) {
            Result::Ok(retdata) => {
                result.append(retdata);
                index += 1;
            },
            Result::Err(revert_reason) => {
                let mut data = array!['argent/multicall-failed', index];
                data.append_all(revert_reason.span());
                panic(data);
            },
        }
    };
    result
}
