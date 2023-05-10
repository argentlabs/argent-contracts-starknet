use array::ArrayTrait;
use array::SpanTrait;

use lib::check_enough_gas;
use option::OptionTrait;
use serde::Serde;
use serde::ArraySerde;
use traits::Into;


impl SpanSerde<T,
impl TSerde: Serde<T>,
impl TDrop: Drop<T>,
impl TCopy: Copy<T>> of Serde<Span<T>> {
    fn serialize(ref serialized: Array<felt252>, mut input: Span<T>) {
        Serde::<usize>::serialize(ref serialized, input.len());
        loop {
            check_enough_gas();
            match input.pop_front() {
                Option::Some(value) => {
                    TSerde::serialize(ref serialized, *value);
                },
                Option::None(_) => {
                    break ();
                },
            };
        }
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<Span<T>> {
        let array = ArraySerde::deserialize(ref serialized)?;
        Option::Some(array.span())
    }

}
