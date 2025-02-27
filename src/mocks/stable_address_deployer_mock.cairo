/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes. Please refrain from relying on the
/// functionality of this contract for any production. 🚨

use starknet::{ClassHash, StorageAddress};

#[starknet::interface]
trait IStableAddressDeployer<TContractState> {
    fn storage_write(ref self: TContractState, address: StorageAddress, value: felt252);
    fn upgrade(ref self: TContractState, new_implementation: ClassHash);
}

#[starknet::contract]
mod StableAddressDeployer {
    use starknet::{ClassHash, StorageAddress, syscalls::{replace_class_syscall, storage_write_syscall}};

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[abi(embed_v0)]
    impl StableAddressDeployerImpl of super::IStableAddressDeployer<ContractState> {
        fn storage_write(ref self: ContractState, address: StorageAddress, value: felt252) {
            storage_write_syscall(0, address, value).unwrap();
        }

        fn upgrade(ref self: ContractState, new_implementation: ClassHash) {
            replace_class_syscall(new_implementation).unwrap();
        }
    }
}
