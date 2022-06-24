%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address

####################
# STORAGE VARIABLES
####################

@storage_var
func stored_number() -> (res: felt):
end

####################
# EXTERNAL FUNCTIONS
####################

@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        number: felt
    ):
    stored_number.write(number)
    return ()
end

@external
func set_number{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        number: felt
    ):
    stored_number.write(number)
    return ()
end

####################
# VIEW FUNCTIONS
####################

@view
func get_number{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } () -> (number: felt):
    let (number) = stored_number.read()
    return (number=number)
end