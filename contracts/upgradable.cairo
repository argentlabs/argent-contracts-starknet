#[contract]
mod Upgradable {
    use contracts::asserts;
    
    struct Storage { 
        implementation: felt,
    }

    fn _get_implementation() -> (felt) {
        return (implementation::read());
    }

    fn _set_implementation(implementation: felt) {
        assert(implementation != 0, 'argent: implementation cannot be zero');
        implementation::write(implementation)
    }

}