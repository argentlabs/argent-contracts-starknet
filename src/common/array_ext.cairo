trait ArrayExtTrait<T> {
    fn append_all(ref self: Array<T>, value: Array<T>);
}

impl ArrayExtImpl<T, impl TDrop: Drop<T>> of ArrayExtTrait<T> {
    fn append_all(ref self: Array<T>, mut value: Array<T>) {
        loop {
            match value.pop_front() {
                Option::Some(item) => self.append(item),
                Option::None => { break; },
            };
        };
    }
}

