%lang starknet
%builtins pedersen range_check ecdsa

from starkware.starknet.common.syscalls import call_contract
from starkware.cairo.common.alloc import alloc

#########################################################################
# The Multicall contract can call an array of view methods on different
# contracts and return the aggregate response as an array.
# Each view method being called must retrun a single felt for the 
# multicall to succeed.  
#########################################################################

struct Call:
    member contract: felt
    member selector: felt
    member calldata_len: felt
    member calldata: felt*
end

@view
func multicall{
        syscall_ptr: felt*,
        range_check_ptr
    } (
        calls_len: felt,
        calls: felt*
    ) -> (result_len: felt, result: felt*):
    alloc_locals

    let (result : felt*) = alloc()
    let (result_len) = call_loop(
        calls_len=calls_len,
        calls=calls,
        result=result
    )

    return (result_len=result_len, result=result)

end

func call_loop{
        syscall_ptr: felt*,
        range_check_ptr
    } (
        calls_len: felt,
        calls: felt*,
        result: felt*
    ) -> (result_len: felt):

    if calls_len == 0: 
        return (0)
    end
    alloc_locals

    let response = call_contract(
        contract_address=[calls],
        function_selector=[calls + 1],
        calldata_size=[calls + 2],
        calldata=&[calls + 3]
    )
    
    array_copy(result, response.retdata_size, response.retdata)

    let (len) = call_loop(
        calls_len=calls_len - (3 + [calls + 2]),
        calls = calls + (3 + [calls + 2]),
        result=result + response.retdata_size
    )
    return (len + response.retdata_size)
end

func array_copy{
        syscall_ptr: felt*,
        range_check_ptr
    } (
        a: felt*,
        b_len: felt,
        b: felt*
    ) -> ():

    assert [a] = [b]

    if b_len == 1:
        return ()
    end

    return array_copy(
        a=a+1,
        b_len=b_len-1,
        b=b+1
    )
end 