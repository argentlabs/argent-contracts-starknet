%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.starknet.common.syscalls import library_call
const SUPPORTS_INTERFACE_SELECTOR = 1184015894760294494673613438913361435336722154500302038630992932234692784845
const ERC165_ACCOUNT_INTERFACE = 0xf10dbd44

@view
func supportsInterface{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    contractClassHash : felt, interfaceId : felt
) -> (success : felt):
    # 165
    if interfaceId == 0x01ffc9a7:
        return (TRUE)
    end
    let (calldata : felt*) = alloc()
    assert calldata[0] = interfaceId
    with_attr error_message("contractClassHash invalid"):
        let (retdata_size : felt, retdata : felt*) = library_call(
            class_hash=contractClassHash,
            function_selector=SUPPORTS_INTERFACE_SELECTOR,
            calldata_size=1,
            calldata=calldata,
        )
    end
    return (success=[retdata])
end
