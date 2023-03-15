use array::ArrayTrait;
use array::SpanTrait;
use gas::get_gas;

trait ArrayTraitExt<T> {
    fn append_all(ref self: Array::<T>, ref arr: Array::<T>);
}

impl ArrayImpl<T, impl TDrop: Drop::<T>> of ArrayTraitExt::<T> {
    fn append_all(ref self: Array::<T>, ref arr: Array::<T>) {
        match get_gas() {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut data = array_new::<felt252>();
                array_append(ref data, 'Out of gas');
                panic(data);
            },
        }
        match arr.pop_front() {
            Option::Some(v) => {
                self.append(v);
                self.append_all(ref arr);
            },
            Option::None(()) => (),
        }
    }
}
