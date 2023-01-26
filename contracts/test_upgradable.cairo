use contracts::Upgradable;

#[test]
#[available_gas(20000)]
fn _get_implementation() {
    assert(Upgradable::_get_implementation() == 0, 'Implementation value should be 0 when not initialized');
}

#[test]
#[available_gas(20000)]
fn _set_implementation() {
    assert(Upgradable::_get_implementation() == 0, 'Implementation value should be 1');
    Upgradable::_set_implementation(42);
    assert(Upgradable::_get_implementation() == 42, 'Implementation value should be 42');
}

#[test]
#[available_gas(20000)]
#[should_panic]
fn _set_implementation_panic_when_zero() {
    Upgradable::_set_implementation(0);
}