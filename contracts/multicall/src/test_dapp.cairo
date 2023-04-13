#[contract]
mod TestDapp {
    use starknet::get_caller_address;
    use starknet::ContractAddress;

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Storage                                          //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    struct Storage {
        stored_number: LegacyMap::<ContractAddress, felt252>, 
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                     External functions                                     //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[external]
    fn set_number(number: felt252) {
        stored_number::write(get_caller_address(), number);
    }

    #[external]
    fn set_number_double(number: felt252) {
        stored_number::write(get_caller_address(), number * 2);
    }

    #[external]
    fn set_number_times3(number: felt252) {
        stored_number::write(get_caller_address(), number * 3);
    }

    #[external]
    fn increase_number(number: felt252) -> felt252 {
        let user = get_caller_address();
        let val = stored_number::read(user);
        let new_number = val + number;
        stored_number::write(user, new_number);
        new_number
    }

    #[external]
    fn throw_error(number: felt252) {
        assert(0 == 1, 'test dapp reverted')
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                       View functions                                       //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[view]
    fn get_number(user: ContractAddress) -> felt252 {
        stored_number::read(user)
    }
}
