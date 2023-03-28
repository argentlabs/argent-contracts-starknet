#[contract]
mod Multicall {
    use box::BoxTrait;
    use starknet::get_block_info;

    use contracts::Call;
    use contracts::execute_multicall;

    #[view]
    fn aggregate(calls: Array<Call>) -> (u64, Array::<felt252>) {
        let block_number = get_block_info().unbox().block_number;
        (block_number, execute_multicall(calls))
    }
}
