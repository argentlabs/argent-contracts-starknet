use starknet::ContractAddress;

#[starknet::interface]
trait ITestDapp<TContractState> {
    fn get_number(self: @TContractState, user: ContractAddress) -> felt252;
    fn set_number(ref self: TContractState, number: felt252);
    fn set_number_double(ref self: TContractState, number: felt252);
    fn set_number_times3(ref self: TContractState, number: felt252);
    fn increase_number(ref self: TContractState, number: felt252) -> felt252;
    fn throw_error(ref self: TContractState, number: felt252);
}

#[starknet::contract]
mod TestDapp {
    use starknet::{get_caller_address, ContractAddress};
    use super::ITestDapp;

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Storage                                          //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[storage]
    struct Storage {
        stored_number: LegacyMap<ContractAddress, felt252>, 
    }


    #[external(v0)]
    impl ITestDappImpl of super::ITestDapp<ContractState> {
        ////////////////////////////////////////////////////////////////////////////////////////////////
        //                                     External functions                                     //
        ////////////////////////////////////////////////////////////////////////////////////////////////
        fn set_number(ref self: ContractState, number: felt252) {
            self.stored_number.write(get_caller_address(), number);
        }

        fn set_number_double(ref self: ContractState, number: felt252) {
            self.stored_number.write(get_caller_address(), number * 2);
        }

        fn set_number_times3(ref self: ContractState, number: felt252) {
            self.stored_number.write(get_caller_address(), number * 3);
        }

        fn increase_number(ref self: ContractState, number: felt252) -> felt252 {
            let user = get_caller_address();
            let val = self.stored_number.read(user);
            let new_number = val + number;
            self.stored_number.write(user, new_number);
            new_number
        }

        fn throw_error(ref self: ContractState, number: felt252) {
            assert(0 == 1, 'test dapp reverted')
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////
        //                                       View functions                                       //
        ////////////////////////////////////////////////////////////////////////////////////////////////

        fn get_number(self: @ContractState, user: ContractAddress) -> felt252 {
            self.stored_number.read(user)
        }
    }
}
