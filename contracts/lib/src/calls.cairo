use array::{ArrayTrait, SpanTrait};
use starknet::{call_contract_syscall, ContractAddress};

#[derive(Drop, Serde)]
struct Call {
    to: ContractAddress,
    selector: felt252,
    calldata: Array<felt252>,
}

fn execute_multicall(calls: Span<Call>) -> Span<Span<felt252>> {
    let mut result: Array<Span<felt252>> = ArrayTrait::new();
    let mut calls = calls;
    let mut idx = 0;
    loop {
        match calls.pop_front() {
            Option::Some(call) => {
                match call_contract_syscall(*call.to, *call.selector, call.calldata.span()) {
                    Result::Ok(mut retdata) => {
                        result.append(retdata);
                        idx = idx + 1;
                    },
                    Result::Err(revert_reason) => {
                        let mut data = ArrayTrait::new();
                        data.append('argent/multicall-failed-');
                        data.append(idx);
                        panic(data);
                    },
                }
            },
            Option::None(_) => {
                break ();
            },
        };
    };
    result.span()
}
