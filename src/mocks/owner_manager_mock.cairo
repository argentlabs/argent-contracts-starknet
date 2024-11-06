use argent::multiowner_account::replace_owners_message::ReplaceOwnersWithOne;

#[starknet::interface]
trait TestInterface<TContractState> {
    fn test(self: @TContractState, my_struct: ReplaceOwnersWithOne) -> felt252;
}
// Todo review and update names here
#[starknet::contract]
mod ReplaceOwnersWithOneWrapper {
    use argent::multiowner_account::replace_owners_message::ReplaceOwnersWithOne;
    use argent::offchain_message::interface::IOffChainMessageHashRev1;

    #[storage]
    struct Storage {}
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[abi(embed_v0)]
    impl IImpl of super::TestInterface<ContractState> {
        fn test(self: @ContractState, my_struct: ReplaceOwnersWithOne) -> felt252 {
            my_struct.get_message_hash_rev_1()
        }
    }
}
