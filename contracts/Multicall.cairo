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

@view
func multicall{
        syscall_ptr: felt*,
        range_check_ptr
    } (
        contract_len: felt,
        contract: felt*,
        selector_len: felt,
        selector: felt*,
        offset_len: felt,
        offset: felt*,
        calldata_len: felt,
        calldata: felt*
    ) -> (result_len: felt, result: felt*):
    alloc_locals

    assert contract_len = selector_len
    assert contract_len = offset_len

    let (local result : felt*) = alloc()
    call_loop(
        num_calls=contract_len,
        contract=contract,
        selector=selector,
        offset=offset,
        calldata=calldata,
        result=result
    )

    return (result_len=contract_len, result=result)

end

func call_loop{
        syscall_ptr: felt*,
        range_check_ptr
    } (
        num_calls: felt,
        contract: felt*,
        selector: felt*,
        offset: felt*,
        calldata: felt*,
        result: felt*
    ) -> ():

    if num_calls == 0: 
        return ()
    end

    let response = call_contract(
        contract_address=[contract],
        function_selector=[selector],
        calldata_size=[offset],
        calldata=calldata
    )

    assert response.retdata_size = 1
    assert [result] = [response.retdata]

    return call_loop(
        num_calls=num_calls - 1,
        contract=contract + 1,
        selector=selector + 1,
        offset=offset + 1,
        calldata=calldata + [offset],
        result=result + 1
    )
end