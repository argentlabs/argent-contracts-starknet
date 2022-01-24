%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_nn
from starkware.starknet.common.syscalls import get_contract_address
from starkware.cairo.common.hash_state import (
    hash_init, hash_finalize, hash_update, hash_update_single
)

const PREFIX_TRANSACTION = 'StarkNet Transaction'

struct Call:
   member to: felt
   member selector: felt
   member calldata_len: felt
   member calldata: felt*
end

@view
func test_get_execute_hash_1{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        to: felt,
        selector: felt,
        calldata_len: felt,
        calldata: felt*,
        nonce: felt
    ) -> (res: felt):
    alloc_locals
    let (calls : Call*) = alloc()
    assert calls[0] = Call(to, selector, calldata_len, calldata)
    let (hash) = get_execute_hash(1, calls, nonce)
    return(res=hash)
end

@view
func test_get_execute_hash_2{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        to_1: felt,
        selector_1: felt,
        calldata_1_len: felt,
        calldata_1: felt*,
        to_2: felt,
        selector_2: felt,
        calldata_2_len: felt,
        calldata_2: felt*,
        nonce: felt
    ) -> (res: felt):
    alloc_locals
    let (local calls : Call*) = alloc()
    assert calls[0] = Call(to_1, selector_1, calldata_1_len, calldata_1)
    assert calls[1] = Call(to_2, selector_2, calldata_2_len, calldata_2)
    let (hash) = get_execute_hash(2, calls, nonce)
    return(res=hash)
end

# @notice Computes the hash of a multicall to the `execute` method.
# @param calls_len The legnth of the array of `Call`
# @param calls A pointer to the array of `Call`
# @param nonce The nonce for the multicall transaction
# @return res The hash of the multicall
func get_execute_hash{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        calls_len: felt,
        calls: Call*,
        nonce: felt
    ) -> (res: felt):
    alloc_locals
    let (account) = get_contract_address()
    let (calls_hash) = hash_call_array(calls_len, calls)
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, PREFIX_TRANSACTION)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, account)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, calls_hash)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, nonce)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (res=res)
    end
end

# @notice Computes the hash of an array of `Call`
# @param calls_len The legnth of the array of `Call`
# @param calls A pointer to the array of `Call`
# @return res The hash of the array of `Call`
func hash_call_array{
        pedersen_ptr: HashBuiltin*
    }(
        calls_len: felt,
        calls: Call*
    ) -> (
        res: felt
    ):
    alloc_locals

    let (hash_array : felt*) = alloc()
    hash_call_loop(calls_len, calls, hash_array)

    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update(hash_state_ptr, hash_array, calls_len)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (res=res)
    end
end

# @notice Turns an array of `Call` into an array of `hash(Call)`
# @param calls_len The legnth of the array of `Call`
# @param calls A pointer to the array of `Call`
# @param hash_array A pointer to the array of `hash(Call)`
func hash_call_loop{
        pedersen_ptr: HashBuiltin*
    } (
        calls_len: felt,
        calls: Call*,
        hash_array: felt*
    ):
    if calls_len == 0:
        return ()
    end
    let this_call = [calls]
    let (calldata_hash) = hash_calldata(this_call.calldata_len, this_call.calldata)
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, this_call.to)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, this_call.selector)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, calldata_hash)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        assert [hash_array] = res
    end
    hash_call_loop(calls_len - 1, calls + Call.SIZE, hash_array + 1)
    return()
end

# @notice Computes the hash of calldata as an array of felt
# @param calldata_len The length of the calldata array
# @param calldata A pointer to the calldata array
# @return the hash of the calldata
func hash_calldata{
        pedersen_ptr: HashBuiltin*
    } (
        calldata_len: felt,
        calldata: felt*,
    ) -> (
        res: felt
    ):
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update(hash_state_ptr, calldata, calldata_len)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (res=res)
    end
end
