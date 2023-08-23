use array::{ArrayTrait, SpanTrait};
use starknet::{call_contract_syscall, account::Call};

use argent::common::array_ext::ArrayExtTrait;

fn execute_multicall(mut calls: Span<Call>) -> Array<Span<felt252>> {
    let mut result: Array<Span<felt252>> = array![];
    let mut idx = 0;
    loop {
        match calls.pop_front() {
            Option::Some(call) => {
                match call_contract_syscall(*call.to, *call.selector, call.calldata.span()) {
                    Result::Ok(retdata) => {
                        result.append(retdata);
                        idx = idx + 1;
                    },
                    Result::Err(revert_reason) => {
                        let mut data = array!['argent/multicall-failed', idx];
                        data.append_all(revert_reason);
                        panic(data);
                    },
                }
            },
            Option::None(_) => {
                break;
            },
        };
    };
    result
}
