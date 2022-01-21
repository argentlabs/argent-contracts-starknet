%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.starknet.common.syscalls import delegate_call, delegate_l1_handler

from contracts.Upgradable import _get_implementation, _set_implementation

####################
# CONSTRUCTOR
####################

@constructor
func constructor{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        implementation: felt
    ):
    _set_implementation(implementation)
    return ()
end

####################
# EXTERNAL FUNCTIONS
####################

@external
@raw_input
@raw_output
func __default__{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        selector : felt,
        calldata_size : felt,
        calldata : felt*
    ) -> (
        retdata_size : felt,
        retdata : felt*
    ):
    let (implementation) = _get_implementation()

    let (retdata_size : felt, retdata : felt*) = delegate_call(
        contract_address=implementation,
        function_selector=selector,
        calldata_size=calldata_size,
        calldata=calldata)
    return (retdata_size=retdata_size, retdata=retdata)
end

@l1_handler
@raw_input
func __l1_default__{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (
        selector : felt,
        calldata_size : felt,
        calldata : felt*
    ):
    let (implementation) = _get_implementation()

    delegate_l1_handler(
        contract_address=implementation,
        function_selector=selector,
        calldata_size=calldata_size,
        calldata=calldata)
    return ()
end

####################
# VIEW FUNCTIONS
####################

@view
func get_implementation{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } () -> (implementation: felt):
    let (implementation) = _get_implementation()
    return (implementation=implementation)
end