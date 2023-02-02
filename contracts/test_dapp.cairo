#[contract]
mod TestDapp {
    // use array::ArrayTrait;
    // use contracts::asserts;
    use contracts::dummy_syscalls;

    /////////////////////
    // STORAGE VARIABLES
    ////////////////////

    struct Storage {
        stored_number: LegacyMap::<felt, felt>, 
    }

    /////////////////////
    // EXTERNAL FUNCTIONS
    /////////////////////

    #[external]
    fn set_number(number: felt) {
        let user = dummy_syscalls::get_caller_address();
        stored_number::write(user, number);
    }

    #[external]
    fn set_number_double(number: felt) {
        let user = dummy_syscalls::get_caller_address();
        stored_number::write(user, number * 2);
    }

    #[external]
    fn set_number_times3(number: felt) {
        let user = dummy_syscalls::get_caller_address();
        stored_number::write(user, number * 3);
    }

    #[external]
    fn increase_number(number: felt) -> felt {
        let user = dummy_syscalls::get_caller_address();
        let val = stored_number::read(user);
        let new_number = val + number;
        stored_number::write(user, new_number);
        new_number
    }

    #[external]
    fn throw_error(number: felt) {
        assert(0 == 1, 'test dapp reverted')
    }

    /////////////////////
    // VIEW FUNCTIONS
    /////////////////////

    #[view]
    fn get_number(user: felt) -> (felt) {
        stored_number::read(user)
    }
}
