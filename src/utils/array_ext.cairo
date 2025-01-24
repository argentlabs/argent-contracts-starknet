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
impl ArrayContains<T, +Drop<T>, +Copy<T>, +PartialEq<T>> of ArrayContainsTrait<T> {
    #[inline(always)]
    fn contains(self: Array<T>, value: T) -> bool {
        let mut found = false;
        for item in self {
            if item == value {
                found = true;
                break;
            }
        };
        found
    }
}

