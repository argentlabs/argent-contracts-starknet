use array::SpanTrait;
use starknet::{ContractAddress};
use argent::session::session_structs::{TokenAmount};
use traits::{Into};

trait Keyable<T, K> {
    fn get_key(self: @T) -> K;
}

impl TokenLimitKeyable of Keyable<TokenAmount, ContractAddress> {
    fn get_key(self: @TokenAmount) -> ContractAddress {
        (*self).contract_address
    }
}

impl ContractAddressKeyable of Keyable<ContractAddress, ContractAddress> {
    fn get_key(self: @ContractAddress) -> ContractAddress {
        *self
    }
}

fn binary_search<
    T,
    K,
    impl TCopy: Copy<T>,
    impl TDrop: Drop<T>,
    impl TKeyable: Keyable<T, K>,
    impl KCopy: Copy<K>,
    impl KDrop: Drop<K>,
    impl KOrd: PartialOrd<K>,
    impl KEq: PartialEq<K>,
>(
    search_span: Span<T>, key: K
) -> Option<T> {
    if (search_span.len() == 0) {
        return Option::None;
    }
    let middle_index = search_span.len() / 2;
    let middle_value: T = *search_span[middle_index];
    let middle_key: K = middle_value.get_key();
    if (middle_key == key) {
        return Option::Some(middle_value);
    }
    if (search_span.len() == 1) {
        return Option::None;
    }
    if (middle_key > key) {
        binary_search(search_span.slice(0, middle_index), key)
    } else {
        let second_half_len = if (search_span.len() % 2 == 0) {
            middle_index
        } else {
            middle_index + 1
        };
        binary_search(search_span.slice(middle_index, second_half_len), key)
    }
}
