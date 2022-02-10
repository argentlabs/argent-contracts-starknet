%lang starknet

from starkware.starknet.common.syscalls import call_contract, get_block_number
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy

#########################################################################
# The Multicall contract can call an array of view methods on different
# contracts and return the aggregate response as an array.
# E.g.
# Input: [to_1, selector_1, data_1_len, data_1, ..., to_N, selector_N, data_N_len, data_N]
# Output: [result_1 + .... + result_N]
#########################################################################

@view
func aggregate{syscall_ptr : felt*, range_check_ptr}(calls_len : felt, calls : felt*) -> (
        block_number : felt, result_len : felt, result : felt*):
    alloc_locals

    let (result : felt*) = alloc()
    let (result_len) = call_loop(calls_len=calls_len, calls=calls, result=result)
    let (block_number) = get_block_number()

    return (block_number=block_number, result_len=result_len, result=result)
end

func call_loop{syscall_ptr : felt*, range_check_ptr}(
        calls_len : felt, calls : felt*, result : felt*) -> (result_len : felt):
    if calls_len == 0:
        return (0)
    end
    alloc_locals

    let response = call_contract(
        contract_address=[calls],
        function_selector=[calls + 1],
        calldata_size=[calls + 2],
        calldata=&[calls + 3])

    memcpy(result, response.retdata, response.retdata_size)

    let (len) = call_loop(
        calls_len=calls_len - (3 + [calls + 2]),
        calls=calls + (3 + [calls + 2]),
        result=result + response.retdata_size)
    return (len + response.retdata_size)
end
