%lang starknet

from starkware.starknet.common.syscalls import call_contract, get_block_number
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from contracts.utils.calls import (
    CallArray,
    execute_multicall,
)


// ////////////////////////////////////////////////////////////////////////
// The Multicall contract can call an array of view methods on different
// contracts and return the aggregate response as an array.
// Input: same as the IAccount.__execute__ 
// @return (block_number, retdata_size, retdata)
//   Where retdata is [len(call_1_data), *call_1_data, len(call_2_data), *call_2_data, ..., len(call_N_data), *call_N_data]
// ///////////////////////////////////////////////////////////////////////
@view
func aggregate{syscall_ptr: felt*, range_check_ptr}(
    call_array_len: felt,
    call_array: CallArray*,
    calldata_len: felt,
    calldata: felt*
) -> (
    block_number: felt, retdata_len: felt, retdata: felt*
) {
    alloc_locals;
    let (retdata_len, retdata) = execute_multicall(call_array_len, call_array, calldata);
    let (block_number) = get_block_number();
    return (block_number=block_number, retdata_len=retdata_len, retdata=retdata);
}
