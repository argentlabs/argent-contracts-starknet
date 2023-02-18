use array::ArrayTrait;

#[contract]
mod FooContract {
    use array::ArrayTrait;
    use serde::Serde;

    #[derive(Copy, Drop)]
    struct Foo {
        bar: felt,
        baz: felt,
    }

    impl FooSerde of Serde::<Foo> {
        fn serialize(ref serialized: Array::<felt>, input: Foo) {
            Serde::<felt>::serialize(ref serialized, input.bar);
            Serde::<felt>::serialize(ref serialized, input.baz);
        }
        fn deserialize(ref serialized: Array::<felt>) -> Option::<Foo> {
            Option::Some(
                Foo {
                    bar: Serde::<felt>::deserialize(ref serialized)?,
                    baz: Serde::<felt>::deserialize(ref serialized)?,
                }
            )
        }
    }

    #[external]
    // fn use_foo(foo: Foo) -> ContractAddress {
    fn use_foo(foo: Foo) {
        assert(starknet::get_caller_address() != 0, 'oops');
        assert(foo.bar == 1, 'oops');
        assert(foo.baz == 2, 'oops');
    }
}

#[test]
#[available_gas(2000000)]
fn test_use_foo() {
    let foo = FooContract::Foo { bar: 1, baz: 2 };
    FooContract::use_foo(foo);
}
