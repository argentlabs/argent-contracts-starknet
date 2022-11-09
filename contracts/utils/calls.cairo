%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_nn
from starkware.starknet.common.syscalls import call_contract
from starkware.cairo.common.bool import TRUE, FALSE

struct Call {
    to: felt,
    selector: felt,
    calldata_len: felt,
    calldata: felt*,
}

// Tmp struct introduced while we wait for Cairo
// to support passing `[Call]` to __execute__
struct CallArray {
    to: felt,
    selector: felt,
    data_offset: felt,
    data_len: felt,
}

func from_call_array_to_call{syscall_ptr: felt*}(
    call_array_len: felt, call_array: CallArray*, calldata: felt*, calls: Call*
) {
    // if no more calls
    if (call_array_len == 0) {
        return ();
    }

    // parse the current call
    assert [calls] = Call(
        to=[call_array].to,
        selector=[call_array].selector,
        calldata_len=[call_array].data_len,
        calldata=calldata + [call_array].data_offset
    );

    // parse the remaining calls recursively
    from_call_array_to_call(
        call_array_len - 1, call_array + CallArray.SIZE, calldata, calls + Call.SIZE
    );
    return ();
}


// @notice Convenience method to convert an execute a call array
// @return response_len: The size of the returned data
// @return response: Data return 
//   in the form [*call_1_data, *call_2_data, ..., *call_N_data]
func execute_call_array{syscall_ptr: felt*}(
    call_array_len: felt, call_array: CallArray*, calldata_len: felt, calldata: felt*
) -> (retdata_len: felt, retdata: felt*) {
    alloc_locals;
    // convert calls
    let (calls: Call*) = alloc();
    from_call_array_to_call(call_array_len, call_array, calldata, calls);

    // execute them
    let (response: felt*) = alloc();
    let (response_len) = execute_calls(call_array_len, calls, response, 0);
    return (retdata_len=response_len, retdata=response);
}


// @notice Executes a list of contract calls recursively.
// @param calls_len The number of calls to execute
// @param calls A pointer to the first call to execute
// @param response The array of felt to populate with the returned data
//   in the form [*call_1_data, *call_2_data, ..., *call_N_data]
// @return response_len The size of the returned data
func execute_calls{syscall_ptr: felt*}(calls_len: felt, calls: Call*, response: felt*, index: felt) -> (
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
    memcpy(
        dst=response,
        src=res.retdata,
        len=res.retdata_size
    );
    // do the next calls recursively
    let (response_len) = execute_calls(
        calls_len=calls_len - 1,
        calls=calls + Call.SIZE,
        response=response + res.retdata_size,
        index=index + 1
    );
    return (response_len + res.retdata_size,);
}

