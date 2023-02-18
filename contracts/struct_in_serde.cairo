use serde::Foo;

#[contract]
mod FooContract {
    use serde::Foo;
    use serde::Serde;

    // #[external]
    fn use_foo(foo: Foo) {
        assert(foo.bar == 1, 'oops');
        assert(foo.baz == 2, 'oops');
    }
}

#[test]
#[available_gas(2000000)]
fn test_use_foo() {
    let foo = Foo { bar: 1, baz: 2 };
    FooContract::use_foo(foo);
}
