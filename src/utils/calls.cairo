use argent::utils::array_ext::ArrayExtTrait;
use starknet::{call_contract_syscall, account::Call};

fn execute_multicall(mut calls: Span<Call>) -> Array<Span<felt252>> {
    let mut result = array![];
    let mut index = 0;
    while let Option::Some(call) = calls
        .pop_front() {
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
