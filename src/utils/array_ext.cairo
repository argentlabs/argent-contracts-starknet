#[generate_trait]
pub impl ArrayExt<T, +Drop<T>, +Copy<T>> of ArrayExtTrait<T> {
    /// @notice Appends multiple elements to an array
    fn append_all(ref self: Array<T>, mut value: Span<T>) {
        for item in value {
            self.append(*item);
        };
    }
}

#[generate_trait]
pub impl SpanContains<T, +Drop<T>, +Copy<T>, +PartialEq<T>> of SpanContainsTrait<T> {
    /// @notice Checks if a Span contains a specific element
    /// @param self The Span to search in
    /// @param item The element to search for
    /// @return True if the element is found in the Span
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

