trait ArrayExtTrait<T> {
    fn append_all(ref self: Array<T>, value: Array<T>);
}


impl ArrayExtImpl<T, +Drop<T>> of ArrayExtTrait<T> {
    fn append_all(ref self: Array<T>, mut value: Array<T>) {
        loop {
            match value.pop_front() {
                Option::Some(item) => self.append(item),
                Option::None => { break; },
            }
        }
    }
}


fn span_to_array<T, +Drop<T>, +Copy<T>>(mut span: Span<T>) -> Array<T> {
    let mut arr: Array<T> = array![];
    match span.pop_front() {
        Option::Some(current) => { arr.append(*current); },
        Option::None => {}
    };
    arr
}
