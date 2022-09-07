%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address

/////////////////////
// STORAGE VARIABLES
////////////////////

@storage_var
func stored_number(user: felt) -> (res: felt) {
}

/////////////////////
// EXTERNAL FUNCTIONS
/////////////////////

@external
func set_number{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(number: felt) {
    let (user) = get_caller_address();
    stored_number.write(user, number);
    return ();
}

@external
func set_number_double{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    number: felt
) {
    let (user) = get_caller_address();
    stored_number.write(user, number * 2);
    return ();
}

@external
func set_number_times3{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    number: felt
) {
    let (user) = get_caller_address();
    stored_number.write(user, number * 3);
    return ();
}

@external
func increase_number{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    number: felt
) {
    let (user) = get_caller_address();
    let (val) = stored_number.read(user);
    stored_number.write(user, val + number);
    return ();
}

@external
func throw_error{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    number: felt
) {
    with_attr error_message("test dapp reverted") {
        assert 0 = 1;
    }
    return();
}

/////////////////////
// VIEW FUNCTIONS
/////////////////////

@view
func get_number{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(user: felt) -> (
    number: felt
) {
    let (number) = stored_number.read(user);
    return (number=number);
}
