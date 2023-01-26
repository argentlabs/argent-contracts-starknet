#[contract]
mod Upgradable {
    use contracts::dummy_syscalls;
    
    struct Storage { 
        implementation: felt,
    }

    fn _get_implementation() -> (felt) {
        return (implementation::read());
    }

    fn _set_implementation(implementation: felt) {
        // assert_not_zero(implementation);
        implementation::write(implementation)
    }

}