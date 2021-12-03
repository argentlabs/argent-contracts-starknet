%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address

####################
# STORAGE VARIABLES
####################

@storage_var
func stored_number(user : felt) -> (res: felt):
end

####################
# EXTERNAL FUNCTIONS
####################

@external
func set_number{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        number: felt
    ):
    let (user) = get_caller_address()
    stored_number.write(user, number)
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
    }(
        user: felt
    ) -> (number: felt):
    let (number) = stored_number.read(user)
    return (number=number)
end