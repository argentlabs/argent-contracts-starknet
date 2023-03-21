use array::ArrayTrait;
use array::ArrayTCloneImpl;
use array::SpanTrait;
use clone::Clone;
use serde::Serde;

// use starknet::call_contract_syscall;
use starknet::ContractAddress;

use contracts::ArrayTraitExt;
use contracts::dummy_syscalls::call_contract_syscall; // TODO remove me + remove me from lib
use contracts::check_enough_gas;

#[derive(Drop)]
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
            match call_contract_syscall(*call.to, *call.selector, call.calldata.clone()) {
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

// Call serialization 

impl CallSerde of Serde::<Call> {
    fn serialize(ref serialized: Array::<felt252>, input: Call) {
        Serde::serialize(ref serialized, input.to);
        Serde::serialize(ref serialized, input.selector);
        Serde::serialize(ref serialized, input.calldata);
    }
    fn deserialize(ref serialized: Span::<felt252>) -> Option::<Call> {
        Option::Some(
            Call {
                to: Serde::deserialize(ref serialized)?,
                selector: Serde::deserialize(ref serialized)?,
                calldata: Serde::deserialize(ref serialized)?,
            }
        )
    }
}

impl ArrayCallSerde of Serde::<Array::<Call>> {
    fn serialize(ref serialized: Array<felt252>, mut input: Array<Call>) {
        Serde::serialize(ref serialized, input.len());
        serialize_array_call_helper(ref serialized, ref input);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<Array<Call>> {
        let length = Serde::deserialize(ref serialized)?;
        let mut arr = ArrayTrait::new();
        deserialize_array_call_helper(ref serialized, arr, length)
    }
}

fn serialize_array_call_helper(ref serialized: Array<felt252>, ref input: Array<Call>) {
    match input.pop_front() {
        Option::Some(value) => {
            Serde::serialize(ref serialized, value);
            serialize_array_call_helper(ref serialized, ref input);
        },
        Option::None(_) => {},
    }
}

fn deserialize_array_call_helper(
    ref serialized: Span<felt252>, mut curr_output: Array<Call>, remaining: felt252
) -> Option<Array<Call>> {
    if remaining == 0 {
        return Option::Some(curr_output);
    }
    curr_output.append(Serde::deserialize(ref serialized)?);
    deserialize_array_call_helper(ref serialized, curr_output, remaining - 1)
}
