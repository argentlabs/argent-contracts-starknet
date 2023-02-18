use debug;
use array::ArrayTrait;

#[derive(Copy, Drop)]
struct Call {
    bar: felt,
    baz: felt,
    calldata: Array::<felt>,
}

impl ArrayCopy of Copy::<Array::<felt>>;
impl ArrayDrop of Drop::<Array::<felt>>;
impl ArrayCallCopy of Copy::<Array::<Call>>;
impl ArrayCallDrop of Drop::<Array::<Call>>;

#[contract]
mod CallContract {
    use serde::Serde;
    use array::ArrayTrait;
    use super::Call;
    use super::ArrayCopy;
    use super::ArrayDrop;
    use super::ArrayCallCopy;
    use super::ArrayCallDrop;

    impl ArrayCallSerde of Serde::<Array::<Call>> {
        fn serialize(ref serialized: Array::<felt>, mut input: Array::<Call>) {
            Serde::<usize>::serialize(ref serialized, input.len());
            serialize_call_array(ref serialized, ref input);
        }
        fn deserialize(ref serialized: Array::<felt>) -> Option::<Array::<Call>> {
            let length = Serde::<felt>::deserialize(ref serialized)?;
            let mut arr = ArrayTrait::new();
            deserialize_call_array(ref serialized, arr, length)
        }
    }

    fn serialize_call_array(ref serialized: Array::<felt>, ref input: Array::<Call>) {
        match get_gas() {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut data = ArrayTrait::new();
                data.append('Out of gas');
                panic(data);
            },
        }
        match input.pop_front() {
            Option::Some(value) => {
                Serde::<felt>::serialize(ref serialized, value.bar);
                Serde::<felt>::serialize(ref serialized, value.baz);
                Serde::<Array::<felt>>::serialize(ref serialized, value.calldata);
                serialize_call_array(ref serialized, ref input);
            },
            Option::None(_) => {},
        }
    }

    fn deserialize_call_array(
        ref serialized: Array::<felt>, mut curr_output: Array::<Call>, remaining: felt
    ) -> Option::<Array::<Call>> {
        match get_gas() {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut data = ArrayTrait::new();
                data.append('Out of gas');
                panic(data);
            },
        }
        if remaining == 0 {
            return Option::<Array::<Call>>::Some(curr_output);
        }

        let bar = Serde::<felt>::deserialize(ref serialized)?;
        let baz = Serde::<felt>::deserialize(ref serialized)?;
        let mut calldata = Serde::<Array::<felt>>::deserialize(ref serialized)?;
        curr_output.append(Call { bar, baz, calldata });

        let used = 3 + u64_to_felt(calldata.len());
        deserialize_call_array(ref serialized, curr_output, remaining - used)
    }

    #[external]
    fn use_calls(ref calls: Array::<Call>) {
        let call = calls.at(0_usize);
        assert(call.bar == 1_felt, 'oops');
    }
}

#[test]
#[available_gas(2000000)]
fn use_some_calls() {
    let mut calldata = ArrayTrait::new();
    calldata.append(1);
    calldata.append(2);
    calldata.append(3);

    let call = Call { bar: 1, baz: 2, calldata };
    let mut calls = ArrayTrait::new();
    calls.append(call);

    CallContract::use_calls(ref calls);
}

