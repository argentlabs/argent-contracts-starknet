//
// TEMP FILE WILL BE REMOVED 
//

use poseidon::poseidon_hash_span;

const U256_TYPE: felt252 = selector!("\"u256\"(\"low\":\"u128\",\"high\":\"u128\")");

trait IStructHashRev1<T> {
    fn get_struct_hash_rev_1(self: @T) -> felt252;
}

impl StructHashU256 of IStructHashRev1<u256> {
    fn get_struct_hash_rev_1(self: @u256) -> felt252 {
        poseidon_hash_span(array![U256_TYPE, (*self.low).into(), (*self.high).into(),].span())
    }
}
