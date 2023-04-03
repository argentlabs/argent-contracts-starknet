use array::ArrayTrait;
use array::SpanTrait;

use contracts::check_enough_gas;

trait ArrayTraitExt<T> {
    fn append_all(ref self: Array::<T>, ref arr: Span::<T>);
}

impl ArrayImpl<T, impl TDrop: Drop<T>, impl TCopy: Copy<T>> of ArrayTraitExt<T> {
    fn append_all(ref self: Array::<T>, ref arr: Span::<T>) {
        check_enough_gas();
        match arr.pop_front() {
            Option::Some(v) => {
                self.append(*v);
                self.append_all(ref arr);
            },
            Option::None(()) => (),
        }
    }
}
