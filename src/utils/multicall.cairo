use starknet::account::Call;

#[starknet::interface]
trait IMulticall<TContractState> {
    fn aggregate(self: @TContractState, calls: Array<Call>) -> (u64, Array<Span<felt252>>);
}

#[starknet::contract]
mod Multicall {
    use argent::utils::calls::execute_multicall;
    use starknet::{info::get_block_number, account::Call};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MulticallImpl of super::IMulticall<ContractState> {
        fn aggregate(self: @ContractState, calls: Array<Call>) -> (u64, Array<Span<felt252>>) {
            (get_block_number(), execute_multicall(calls.span()))
        }
    }
}
