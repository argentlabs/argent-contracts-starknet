// Tries to deserialize the given data into.
// The data must only contain the returned value and nothing else
fn full_deserialize<E, impl ESerde: Serde<E>, impl EDrop: Drop<E>>(data: Span<felt252>) -> Option<E> {
    let mut data = data;
    let parsed_value: E = ESerde::deserialize(ref data).expect('argent/undeserializable');
    if data.is_empty() {
        Option::Some(parsed_value)
    } else {
        Option::None
    }
}

fn serialize<E, impl ESerde: Serde<E>>(value: @E) -> Array<felt252> {
    let mut output = array![];
    ESerde::serialize(value, ref output);
    output
}
