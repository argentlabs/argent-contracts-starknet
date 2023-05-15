#[contract]
mod Multicall {
    use box::BoxTrait;
    use starknet::get_block_info;
    use array::SpanTrait;
    use array::ArrayTrait;

    use lib::Call;
    use lib::execute_multicall;
    use lib::SpanSerde;

    #[view]
    fn aggregate(calls: Array<Call>) -> (u64, Span<Span<felt252>>) {
        let block_number = get_block_info().unbox().block_number;
        (block_number, execute_multicall(calls.span()))
    }
}
