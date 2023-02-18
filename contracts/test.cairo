#[contract]
mod SomeContract {
    use contracts::dummy_syscalls;
    use array::ArrayTrait;
    use option::OptionTrait;
    use serde::Serde;

    // Generic structs
    #[derive(Copy, Drop)]
    struct Test {
        a: felt,
        arr: Array::<felt>,
    }
    impl ArrayCopy of Copy::<Array::<felt>>;
    impl ArrayDrop of Drop::<Array::<Test>>;

    impl TestSerde of Serde::<Test> {
        fn serialize(ref serialized: Array::<felt>, input: Test) {
            Serde::<felt>::serialize(ref serialized, input.a);
            Serde::<Array::<felt>>::serialize(ref serialized, input.arr);
        }
        fn deserialize(ref serialized: Array::<felt>) -> Option::<Test> {
            Option::Some(
                Test {
                    a: Serde::<felt>::deserialize(ref serialized)?,
                    arr: Serde::<Array::<felt>>::deserialize(ref serialized)?,
                }
            )
        }
    }

    impl ArrayTestSerde of Serde::<Array::<Test>> {
        fn serialize(ref serialized: Array::<felt>, mut input: Array::<Test>) {
            Serde::<usize>::serialize(ref serialized, input.len());
            serialize_array_call_helper(ref serialized, ref input);
        }
        fn deserialize(ref serialized: Array::<felt>) -> Option::<Array::<Test>> {
            let length = Serde::<felt>::deserialize(ref serialized)?;
            let mut arr = ArrayTrait::new();
            deserialize_array_call_helper(ref serialized, arr, length)
        }
    }


    fn serialize_array_call_helper(ref serialized: Array::<felt>, ref input: Array::<Test>) {
        match input.pop_front() {
            Option::Some(value) => {
                Serde::<Test>::serialize(ref serialized, value);
                serialize_array_call_helper(ref serialized, ref input);
            },
            Option::None(_) => {},
        }
    }

    fn deserialize_array_call_helper(
        ref serialized: Array::<felt>, mut curr_output: Array::<Test>, remaining: felt
    ) -> Option::<Array::<Test>> {
        if remaining == 0 {
            return Option::<Array::<Test>>::Some(curr_output);
        }
        curr_output.append(Serde::<Test>::deserialize(ref serialized)?);
        deserialize_array_call_helper(ref serialized, curr_output, remaining - 1)
    }

    #[view]
    fn aggregate(ref calls: Array::<Test>) -> felt {
        calls.at(0_usize).a
    }
}


use array::ArrayTrait;
use SomeContract::Test;

#[test]
#[available_gas(2000000)]
fn aggregate() {
    let mut all = array_new::<Test>();
    let mut arr = array_new();
    arr.append(12);
    all.append(Test { a: 1, arr: arr });
    SomeContract::aggregate(ref all);
}

