/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes.
/// Please refrain from relying on the functionality of this contract for any production code. 🚨
use starknet::ContractAddress;

#[starknet::interface]
trait IMockDapp<TContractState> {
    fn set_number(ref self: TContractState, number: felt252);
    fn double_number(ref self: TContractState);
    fn increase_number(ref self: TContractState, number: felt252);

    fn get_number(self: @TContractState, user: ContractAddress) -> felt252;
}

#[starknet::contract]
mod MockDapp {
    use starknet::{
        ContractAddress, get_caller_address, storage::Map, storage::{StorageMapReadAccess, StorageMapWriteAccess},
    };

    #[storage]
    struct Storage {
        stored_number: Map<ContractAddress, felt252>,
        revoked: Map<ContractAddress, felt252>,
    }

    #[abi(embed_v0)]
    impl MockDappImpl of super::IMockDapp<ContractState> {
        fn set_number(ref self: ContractState, number: felt252) {
            self.stored_number.write(get_caller_address(), number);
        }

        fn double_number(ref self: ContractState) {
            let user = get_caller_address();
            let val = self.stored_number.read(get_caller_address());
            self.stored_number.write(user, val * 2);
        }

        fn increase_number(ref self: ContractState, number: felt252) {
            let user = get_caller_address();
            let val = self.stored_number.read(user);
            self.stored_number.write(user, val + number);
        }

        fn get_number(self: @ContractState, user: ContractAddress) -> felt252 {
            self.stored_number.read(user)
        }
    }
}
