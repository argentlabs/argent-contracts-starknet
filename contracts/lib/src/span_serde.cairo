use array::ArrayTrait;
use array::SpanTrait;

use option::OptionTrait;
use serde::{Serde, serialize_array_helper};
use serde::ArraySerde;
use traits::Into;


// Eventually this will be implemented in the cairo core
impl SpanSerde<T,
impl TSerde: Serde<T>,
impl TDrop: Drop<T>,
impl TCopy: Copy<T>> of Serde<Span<T>> {
    fn serialize(self: @Span<T>, ref output: Array<felt252>) {
        (*self).len().serialize(ref output);
        serialize_array_helper(*self, ref output);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<Span<T>> {
        Option::Some(ArraySerde::deserialize(ref serialized)?.span())
    }
}
