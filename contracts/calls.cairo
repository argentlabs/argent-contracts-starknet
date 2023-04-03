use array::ArrayTrait;
use array::SpanTrait;

// use starknet::call_contract_syscall;
use starknet::ContractAddress;

use contracts::ArrayTraitExt;
use contracts::dummy_syscalls::call_contract_syscall; // TODO remove me + remove me from lib
use contracts::check_enough_gas;

#[derive(Drop, Serde)]
struct Call {
    to: ContractAddress,
    selector: felt252,
    calldata: Array<felt252>,
}

fn execute_multicall(calls: Array<Call>) -> Array<felt252> {
    let mut result = ArrayTrait::new();
    let mut calls = calls;
    let mut idx = 0;
    loop {
        check_enough_gas();
        match calls.pop_front() {
            Option::Some(call) => {
                match call_contract_syscall(call.to, call.selector, call.calldata.span()) {
                    Result::Ok(mut retdata) => {
                        result.append_all(ref retdata);
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
    result
}
