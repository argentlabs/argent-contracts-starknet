use starknet::account::Call;
use lib::execute_multicall;

#[starknet::interface]
trait IMulticall<TContractState> {
    fn aggregate(self: @TContractState, calls: Array<Call>) -> (u64, Array<Span<felt252>>);
}

#[starknet::contract]
mod Multicall {
    use box::BoxTrait;
    use starknet::get_block_info;
    use array::{SpanTrait, ArrayTrait};

    use starknet::account::Call;
    use lib::{execute_multicall};

    #[storage]
    struct Storage {}

    #[view]
    fn aggregate(calls: Array<Call>) -> (u64, Array<Span<felt252>>) {
        let block_number = get_block_info().unbox().block_number;
        (block_number, execute_multicall(calls.span()))
    }
}
