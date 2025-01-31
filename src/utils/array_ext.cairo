#[generate_trait]
impl ArrayExt<T, +Drop<T>, +Copy<T>> of ArrayExtTrait<T> {
    #[inline(always)]
    fn append_all(ref self: Array<T>, mut value: Span<T>) {
        while let Option::Some(item) = value.pop_front() {
            self.append(*item);
        };
    }
}

#[generate_trait]
impl SpanContains<T, +Drop<T>, +Copy<T>, +PartialEq<T>> of SpanContainsTrait<T> {
    fn contains(self: @Span<T>, item: T) -> bool {
        let mut found = false;
        for self_item in *self {
            if item == *self_item {
                found = true;
                break;
            }
        };
        found
    }
}

