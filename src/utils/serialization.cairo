// Tries to deserialize the given data into.
// The data must only contain the returned value and nothing else
fn full_deserialize<E, impl ESerde: Serde<E>, impl EDrop: Drop<E>>(mut data: Span<felt252>) -> Option<E> {
    let parsed_value: E = ESerde::deserialize(ref data)?;
    if data.is_empty() {
        Option::Some(parsed_value)
    } else {
        Option::None
    }
}

fn full_deserialize_or_error<E, impl ESerde: Serde<E>, impl EDrop: Drop<E>>(
    mut data: Span<felt252>, panic_error: felt252
) -> E {
    let parsed_value: E = ESerde::deserialize(ref data).expect(panic_error);
    assert(data.is_empty(), panic_error);
    parsed_value
}


fn serialize<E, impl ESerde: Serde<E>>(value: @E) -> Array<felt252> {
    let mut output = array![];
    ESerde::serialize(value, ref output);
    output
}
