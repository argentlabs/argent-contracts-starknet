use array::ArrayTrait;
use array::SpanTrait;

// use starknet::call_contract_syscall;
use starknet::ContractAddress;

use lib::ArrayTraitExt;
use lib::dummy_syscalls::call_contract_syscall; // TODO remove me + remove me from lib
use lib::check_enough_gas;

#[derive(Drop, Serde)]
struct Call {
    to: ContractAddress,
    selector: felt252,
    calldata: Array<felt252>,
}

fn execute_multicall(calls: Array<Call>) -> Array<felt252> {
    let mut result = ArrayTrait::new();
    execute_multicall_loop(calls.span(), ref result, 0);
    result
}

fn execute_multicall_loop(mut calls: Span<Call>, ref result: Array<felt252>, index: felt252) {
    check_enough_gas();
    match calls.pop_front() {
        Option::Some(call) => {
            match call_contract_syscall(*call.to, *call.selector, call.calldata.span()) {
                Result::Ok(retdata) => {
                    let mut mut_retdata = retdata;
                    result.append_all(ref mut_retdata);
                    execute_multicall_loop(calls, ref result, index + 1);
                },
                Result::Err(revert_reason) => {
                    let mut data = ArrayTrait::new();
                    data.append('argent/multicall-failed-');
                    data.append(index);
                    panic(data);
                },
            }
        },
        Option::None(_) => (),
    }
}
