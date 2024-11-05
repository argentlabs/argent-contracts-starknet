use snforge_std::{declare, ContractClassTrait, ContractClass, start_cheat_caller_address_global, DeclareResultTrait};
use starknet::{get_contract_address, ContractAddress};

fn test() -> ContractAddress {
    get_contract_address()
}

#[starknet::interface]
trait TestInterface<TContractState> {
    fn test(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod TestContract {
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    impl IImpl of super::TestInterface<ContractState> {
        fn test(self: @ContractState) -> ContractAddress {
            super::test()
        }
    }
}

#[test]
fn test_simple() {
    let class_hash = *declare("TestContract").expect('Fail decl TestContract').contract_class();
    let (contract_address, _) = class_hash.deploy(@array![]).expect('Multisig deployment fail');
    start_cheat_caller_address_global(contract_address);
    let contract = TestInterfaceDispatcher { contract_address };
    assert_eq!(contract.test(), test());
}
