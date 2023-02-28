use array::ArrayTrait;

fn span_to_array(span: @Array::<felt>) -> Array::<felt> {
    let mut output = ArrayTrait::new();
    span_to_array_helper(span, output, 0_usize)
}

fn span_to_array_helper(
    span: @Array::<felt>, mut curr_output: Array::<felt>, index: usize
) -> Array::<felt> {
    match try_fetch_gas() {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut data = ArrayTrait::new();
            data.append('Out of gas');
            panic(data);
        },
    }
    if index == span.len() {
        return curr_output;
    }
    curr_output.append(*(span.at(index)));
    span_to_array_helper(span, curr_output, index + 1_usize)
}
