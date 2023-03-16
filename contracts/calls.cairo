use array::ArrayTrait;
use array::ArrayTCloneImpl;
use array::SpanTrait;
use gas::get_gas;
use serde::Serde;
use clone::Clone;

// use starknet::call_contract_syscall;
use starknet::ContractAddress;
use starknet::contract_address::ContractAddressSerde;

use contracts::ArrayTraitExt;
use contracts::dummy_syscalls::call_contract;

#[derive(Drop)]
struct Call {
    to: ContractAddress,
    selector: felt252,
    calldata: Array<felt252>,
}

fn execute_multicall(calls: Array<Call>) -> Array<felt252> {
    let mut result = ArrayTrait::new();
    execute_multicall_loop(calls.span(), ref arr);
    arr
}

fn execute_multicall_loop(mut calls: Span<Call>, ref array: Array<felt252>) {
    match get_gas() {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut data = ArrayTrait::new();
            array_append(ref data, 'Out of gas');
            panic(data);
        },
    }
    match calls.pop_front() {
        Option::Some(call) => {
            // let mut current_call = call_contract_syscall(
            //     *call.to, *call.selector, call.calldata.clone()
            // ).unwrap_syscall();

            let mut current_call = call_contract(*call.to, *call.selector, call.calldata.clone());
            array.append_all(ref current_call);
            // TODO Should I trigger event to say "Hey event X done" for ui it'll be noice I guesss?
            execute_multicall_loop(calls, ref array);
        },
        Option::None(_) => (),
    }
}
// Call serialization 

impl CallSerde of Serde::<Call> {
    fn serialize(ref serialized: Array::<felt252>, input: Call) {
        let ref_input = @input;
        Serde::serialize(ref serialized, *ref_input.to);
        Serde::serialize(ref serialized, *ref_input.selector);
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
