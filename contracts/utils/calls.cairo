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

// Enumeration of possible CallData prefix for smart multicall
struct CallDataType {
    VALUE: felt,
    REF: felt,
    CALL_REF: felt,
    FUNC: felt,
    FUNC_CALL: felt,
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

func execute_plain_multicall{syscall_ptr: felt*}(
    call_array_len: felt, call_array: CallArray*, calldata: felt*
) -> (response_len: felt, response: felt*) {
    alloc_locals;
    if (call_array_len == 0) {
        let (response) = alloc();
        return (0, response);
    }

    // call recursively all previous calls
    let (response_len, response: felt*) = execute_plain_multicall(call_array_len - 1, call_array, calldata);

    // handle the last call
    let last_call = call_array[call_array_len - 1];

    // call the last call
    with_attr error_message("multicall {call_array_len} failed") {
        let res = call_contract(
            contract_address=last_call.to,
            function_selector=last_call.selector,
            calldata_size=last_call.data_len,
            calldata=calldata + last_call.data_offset,
        );
    }

    // store response data
    memcpy(response + response_len, res.retdata, res.retdata_size);
    return (response_len + res.retdata_size, response);
}

func execute_smart_multicall{syscall_ptr: felt*}(
    call_array_len: felt, call_array: CallArray*, calldata: felt*
) -> (
    offsets_len: felt, offsets: felt*, response_len: felt, response: felt*
) {
    alloc_locals;
    if (call_array_len == 0) {
        let (response) = alloc();
        let (offsets) = alloc();
        assert offsets[0] = 0;
        return (1, offsets, 0, response);
    }

    // call recursively all previous calls
    let (offsets_len, offsets: felt*, response_len, response: felt*) = execute_smart_multicall(call_array_len - 1, call_array, calldata);

    // handle the last call
    let last_call = call_array[call_array_len - 1];

    let (inputs: felt*) = alloc();
    compile_call_inputs(
        inputs, last_call.data_len, calldata + last_call.data_offset, offsets_len, offsets, response
    );

    // call the last call
    with_attr error_message("multicall {call_array_len} failed") {
        let res = call_contract(
            contract_address=last_call.to,
            function_selector=last_call.selector,
            calldata_size=last_call.data_len,
            calldata=inputs,
        );
    }

    // store response data
    memcpy(response + response_len, res.retdata, res.retdata_size);
    assert offsets[offsets_len] = res.retdata_size + offsets[offsets_len - 1];
    return (offsets_len + 1, offsets, response_len + res.retdata_size, response);
}

func compile_call_inputs{syscall_ptr: felt*}(
    inputs: felt*,
    call_len,
    shifted_calldata: felt*,
    offsets_len: felt,
    offsets: felt*,
    response: felt*,
) -> () {
    if (call_len == 0) {
        return ();
    }

    tempvar type = [shifted_calldata];
    if (type == CallDataType.VALUE) {
        // 1 -> value
        assert [inputs] = shifted_calldata[1];
        return compile_call_inputs(
            inputs + 1, call_len - 1, shifted_calldata + 2, offsets_len, offsets, response
        );
    }

    if (type == CallDataType.REF) {
        // 1 -> shift
        assert [inputs] = response[shifted_calldata[1]];
        return compile_call_inputs(
            inputs + 1, call_len - 1, shifted_calldata + 2, offsets_len, offsets, response
        );
    }

    if (type == CallDataType.CALL_REF) {
        // 1 -> call_id, 2 -> shift
        let call_id = shifted_calldata[1];
        let shift = shifted_calldata[2];
        let call_shift = offsets[call_id];

        let value = response[offsets[shifted_calldata[1]] + shifted_calldata[2]];
        assert [inputs] = value;
        return compile_call_inputs(
            inputs + 1, call_len - 1, shifted_calldata + 3, offsets_len, offsets, response
        );
    }

    // should not be called (todo: put the default case)
    assert 1 = 0;
    ret;
}

