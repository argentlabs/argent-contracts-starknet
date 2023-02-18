use array::ArrayTrait;

impl ArrayFooDrop of Drop::<Array::<Foo>>;

#[derive(Copy, Drop)]
struct Foo {
    bar: felt,
    baz: felt,
}

#[contract]
mod FooContract {
    use array::ArrayTrait;
    use super::Foo;

    // #[external] // commented to avoid serde
    fn use_foos(ref foos: Array::<Foo>) {
        assert(foos.len() == 2_usize, 'oops');
    }
}
