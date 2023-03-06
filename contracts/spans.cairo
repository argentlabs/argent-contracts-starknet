use array::ArrayTrait;
use array::SpanTrait;
use gas::get_gas;

fn span_to_array(span: Span<felt>) -> Array<felt> {
    let mut output = ArrayTrait::new();
    span_to_array_helper(span, output)
}

fn span_to_array_helper(mut span: Span<felt>, mut curr_output: Array<felt>) -> Array<felt> {
    match get_gas() {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut data = ArrayTrait::new();
            data.append('Out of gas');
            panic(data);
        },
    }
    match span.pop_front() {
        Option::Some(i) => {
            curr_output.append(*i);
            span_to_array_helper(span, curr_output)
        },
        Option::None(_) => (curr_output),
    }
}
