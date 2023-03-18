use array::ArrayTrait;
use serde::Serde;
use starknet::ContractAddress;
use starknet::contract_address::ContractAddressSerde;

#[derive(Drop)]
struct Call {
    to: ContractAddress,
    selector: felt252,
    calldata: Array<felt252>,
}

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
