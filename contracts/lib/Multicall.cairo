%lang starknet

from starkware.starknet.common.syscalls import call_contract, get_block_number
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from contracts.utils.calls import (
    Call,
    CallArray,
    from_call_array_to_call,
)


// ////////////////////////////////////////////////////////////////////////
// The Multicall contract can call an array of view methods on different
// contracts and return the aggregate response as an array.
// Input: same as the IAccount.__execute__ 
// @return (block_number, retdata_size, retdata)
//   Where retdata is [len(call_1_data), *call_1_data, len(call_1_data), *call_2_data, ..., len(call_N_data), *call_N_data]
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
    let (retdata_len, retdata) = execute_call_array_detailed(call_array_len, call_array, calldata_len, calldata);
    let (block_number) = get_block_number();
    return (block_number=block_number, retdata_len=retdata_len, retdata=retdata);
}


// @notice Convenience method to convert an execute a call array
// @return response_len: The size of the returned data
// @return response: Data return 
//   in the form [len(call_1_data), *call_1_data, len(call_1_data), *call_2_data, ..., len(call_N_data), *call_N_data]
func execute_call_array_detailed{syscall_ptr: felt*}(
    call_array_len: felt, call_array: CallArray*, calldata_len: felt, calldata: felt*
) -> (retdata_len: felt, retdata: felt*) {
    alloc_locals;
    // convert calls
    let (calls: Call*) = alloc();
    from_call_array_to_call(call_array_len, call_array, calldata, calls);

    // execute them
    let (response: felt*) = alloc();
    let (response_len) = execute_calls_detailed(call_array_len, calls, response, 0);
    return (retdata_len=response_len, retdata=response);
}


// @notice Executes a list of contract calls recursively.
// @param calls_len The number of calls to execute
// @param calls A pointer to the first call to execute
// @param response The array of felt to populate with the returned data
//   in the form [len(call_1_data), *call_1_data, len(call_1_data), *call_2_data, ..., len(call_N_data), *call_N_data]
// @return response_len The size of the returned data
func execute_calls_detailed{syscall_ptr: felt*}(calls_len: felt, calls: Call*, response: felt*, index: felt) -> (
    response_len: felt
) {
    alloc_locals;

    // if no more calls
    if (calls_len == 0) {
        return (0,);
    }

    // do the current call
    let this_call: Call = [calls];
    with_attr error_message("multicall {index} failed") {
        let res = call_contract(
            contract_address=this_call.to,
            function_selector=this_call.selector,
            calldata_size=this_call.calldata_len,
            calldata=this_call.calldata,
        );
    }
    // copy the result in response
    assert [response] = res.retdata_size;
    memcpy(
        dst=response + 1,
        src=res.retdata,
        len=res.retdata_size
    );
    // do the next calls recursively
    let (response_len) = execute_calls_detailed(
        calls_len=calls_len - 1,
        calls=calls + Call.SIZE,
        response=response + res.retdata_size + 1,
        index=index + 1
    );
    return (response_len + res.retdata_size + 1,);
}
