use contracts::TestDapp;
use contracts::dummy_syscalls::get_caller_address;
use debug::print_felt;

const MAX_FELT: felt = 3618502788666131213697322783095070105623107215331596699973092056135872020480;

#[test]
#[available_gas(2000000)]
fn get_number() {
    assert(TestDapp::get_number(get_caller_address()) == 0, 'Default value should be zero');
}

#[test]
#[available_gas(2000000)]
fn set_number() {
    TestDapp::set_number(42);
    assert(TestDapp::get_number(get_caller_address()) == 42, 'Value should be 42');
}

#[test]
#[available_gas(2000000)]
fn set_number_neg() {
    TestDapp::set_number(-42);
    assert(TestDapp::get_number(get_caller_address()) == -42, 'Value should be -42');
}

#[test]
#[available_gas(2000000)]
fn set_number_double() {
    TestDapp::set_number_double(42);
    assert(TestDapp::get_number(get_caller_address()) == 42 * 2, 'Value should be 42 * 2');
}

#[test]
#[available_gas(2000000)]
fn set_number_double_neg() {
    TestDapp::set_number_double(-42);
    assert(TestDapp::get_number(get_caller_address()) == -42 * 2, 'Value should be -42 * 2');
    assert(TestDapp::get_number(get_caller_address()) == 3618502788666131213697322783095070105623107215331596699973092056135872020397, 'Value should be 3618502788666131213697322783095070105623107215331596699973092056135872020397');
}

#[test]
#[available_gas(2000000)]
fn set_number_double_overflow() {
    TestDapp::set_number_double(MAX_FELT);
    assert(TestDapp::get_number(get_caller_address()) == MAX_FELT * 2, 'Value should be MAX_FELT * 2');
    assert(TestDapp::get_number(get_caller_address()) == MAX_FELT - 1, 'Value should be MAX_FELT - 1');
}

#[test]
#[available_gas(2000000)]
fn set_number_times3() {
    TestDapp::set_number_times3(42);
    assert(TestDapp::get_number(get_caller_address()) == 42 * 3, 'Value should be 42 * 3');
}

#[test]
#[available_gas(2000000)]
fn set_number_times3_neg() {
    TestDapp::set_number_times3(-42);
    assert(TestDapp::get_number(get_caller_address()) == -42 * 3, 'Value should be -42 * 3');
    assert(TestDapp::get_number(get_caller_address()) == 3618502788666131213697322783095070105623107215331596699973092056135872020355, 'Value should be 3618502788666131213697322783095070105623107215331596699973092056135872020355');
}

#[test]
#[available_gas(2000000)]
fn set_number_times3_overflow() {
    TestDapp::set_number_times3(MAX_FELT);
    assert(TestDapp::get_number(get_caller_address()) == MAX_FELT * 3, 'Value should be MAX_FELT * 3');
    assert(TestDapp::get_number(get_caller_address()) == MAX_FELT - 2, 'Value should be MAX_FELT - 2');
}

#[test]
#[available_gas(2000000)]
fn increase_number() {
    TestDapp::set_number(40);
    TestDapp::increase_number(2);
    assert(TestDapp::get_number(get_caller_address()) == 42, 'Value should be 42');
}

#[test]
#[available_gas(2000000)]
fn increase_number_on_default() {
    TestDapp::increase_number(42);
    assert(TestDapp::get_number(get_caller_address()) == 42, 'Value should be 42');
}

#[test]
#[available_gas(2000000)]
fn increase_number_overflow() {
    TestDapp::set_number(43);
    TestDapp::increase_number(MAX_FELT);
    assert(TestDapp::get_number(get_caller_address()) == 42, 'Value should be 42');
}

#[test]
#[available_gas(2000000)]
fn increase_number_overflow_from_negatif() {
    TestDapp::set_number(-1);
    TestDapp::increase_number(43);
    assert(TestDapp::get_number(get_caller_address()) == 42, 'Value should be 42');
}

#[test]
#[available_gas(2000000)]
fn increase_number_overflow_from_max_felt() {
    TestDapp::set_number(MAX_FELT);
    TestDapp::increase_number(43);
    assert(TestDapp::get_number(get_caller_address()) == 42, 'Value should be 42');
}



#[test]
#[available_gas(2000000)]
fn increase_number_neg() {
    TestDapp::set_number(43);
    TestDapp::increase_number(-1); 
    assert(TestDapp::get_number(get_caller_address()) == 42, 'Value should be 42');
}

#[test]
#[available_gas(2000000)]
fn increase_number_neg_overflow() {
    TestDapp::set_number(41);
    TestDapp::increase_number(-42);
    assert(TestDapp::get_number(get_caller_address()) == -1, 'Value should be -1');
    assert(TestDapp::get_number(get_caller_address()) == MAX_FELT, 'Value should be MAX_FELT');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn throw_error() {
    TestDapp::throw_error(42);
}

