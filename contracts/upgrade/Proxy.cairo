%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import library_call, library_call_l1_handler

from contracts.upgrade.Upgradable import _get_implementation, _set_implementation

const VALIDATE_DEPLOY_SELECTOR = 1554466106298962091002569854891683800203193677547440645928814916929210362005;

/////////////////////
// CONSTRUCTOR
/////////////////////

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    implementation: felt, selector: felt, calldata_len: felt, calldata: felt*
) {
    _set_implementation(implementation);
    library_call(
        class_hash=implementation,
        function_selector=selector,
        calldata_size=calldata_len,
        calldata=calldata,
    );
    return ();
}

/////////////////////
// EXTERNAL FUNCTIONS
/////////////////////

@external
func __validate_deploy__{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
} (
    class_hash: felt,
    salt: felt,
    implementation: felt,
    selector: felt,
    calldata_len: felt,
    calldata: felt*
) {
    let (implementation) = _get_implementation();
    
    let (inner_calldata: felt*) = alloc();
    assert inner_calldata[0] = class_hash;
    assert inner_calldata[1] = salt;
    
    library_call(
        class_hash=implementation,
        function_selector=VALIDATE_DEPLOY_SELECTOR,
        calldata_size=2,
        calldata=inner_calldata,
    );
    return ();
}

@external
@raw_input
@raw_output
func __default__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    selector: felt, calldata_size: felt, calldata: felt*
) -> (retdata_size: felt, retdata: felt*) {
    let (implementation) = _get_implementation();

    let (retdata_size: felt, retdata: felt*) = library_call(
        class_hash=implementation,
        function_selector=selector,
        calldata_size=calldata_size,
        calldata=calldata,
    );
    return (retdata_size=retdata_size, retdata=retdata);
}

@l1_handler
@raw_input
func __l1_default__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    selector: felt, calldata_size: felt, calldata: felt*
) {
    let (implementation) = _get_implementation();

    library_call_l1_handler(
        class_hash=implementation,
        function_selector=selector,
        calldata_size=calldata_size,
        calldata=calldata,
    );
    return ();
}

/////////////////////
// VIEW FUNCTIONS
/////////////////////

@view
func get_implementation{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    implementation: felt
) {
    let (implementation) = _get_implementation();
    return (implementation=implementation);
}
