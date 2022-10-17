%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_nn, assert_not_equal
from starkware.cairo.common.math_cmp import is_not_zero
from starkware.starknet.common.syscalls import (
    library_call,
    call_contract,
    get_tx_info,
    get_contract_address,
    get_caller_address,
    get_block_timestamp,
)
from starkware.cairo.common.bool import TRUE, FALSE
from contracts.plugins.IPlugin import IPlugin
from contracts.account.library import CallArray, Call

/////////////////////
// CONSTANTS
/////////////////////

const NAME = 'PluginAccount';
const VERSION = '0.0.1';

const IS_VALID_SIGNATURE_SELECTOR = 1138073982574099226972715907883430523600275391887289231447128254784345409857;
const SUPPORTS_INTERFACE_SELECTOR = 1184015894760294494673613438913361435336722154500302038630992932234692784845;
const INITIALIZE_SELECTOR = 215307247182100370520050591091822763712463273430149262739280891880522753123;
const ERC165_ACCOUNT_INTERFACE_ID = 0x3943f10f;

/////////////////////
// EVENTS
/////////////////////

@event
func account_created(account: felt) {
}

@event
func account_upgraded(new_implementation: felt) {
}

@event
func transaction_executed(hash: felt, response_len: felt, response: felt*) {
}

/////////////////////
// STORAGE VARIABLES
/////////////////////

@storage_var
func _current_plugin() -> (res: felt) {
}

@storage_var
func _plugins(plugin: felt) -> (res: felt) {
}

/////////////////////
// PROTOCOL
/////////////////////

@external
func __validate__{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(
    call_array_len: felt, call_array: CallArray*, calldata_len: felt, calldata: felt*
) {
    assert_initialized();

    let (plugin_id) = use_plugin();
    validate_with_plugin(
        plugin_id, call_array_len, call_array, calldata_len, calldata
    );
    return ();
}

@external
func __validate_deploy__{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    range_check_ptr
} (
    class_hash: felt,
    ctr_args_len: felt,
    ctr_args: felt*,
    salt: felt
) {
    alloc_locals;
    // get the tx info
    let (tx_info) = get_tx_info();
    // validate the signer signature only
    let (is_valid) = isValidSignature(tx_info.transaction_hash, tx_info.signature_len, tx_info.signature);
    with_attr error_message("PluginAccount: invalid deploy") {
        assert_not_zero(is_valid);
    }
    return ();
}

@external
@raw_output
func __execute__{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
} (
    call_array_len: felt, call_array: CallArray*, calldata_len: felt, calldata: felt*
) -> (retdata_size: felt, retdata: felt*) {
    alloc_locals;

    assert_non_reentrant();

    let (response_len, response) = execute(
        call_array_len, call_array, calldata_len, calldata
    );
    return (retdata_size=response_len, retdata=response);
}

@external
func __validate_declare__{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    range_check_ptr
} (
    class_hash: felt
) {
    // todo
    return ();
}

/////////////////////
// EXTERNAL FUNCTIONS
/////////////////////

@external
func initialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, plugin_calldata_len: felt, plugin_calldata: felt*
) {
    let (is_initialized) = _plugins.read(0);
    with_attr error_message("PluginAccount: already initialized") {
        assert is_initialized = FALSE;
    }

    _plugins.write(0, plugin);
    _plugins.write(plugin, 1);

    let (self) = get_contract_address();
    account_created.emit(self);

    initialize_plugin(plugin, plugin_calldata_len, plugin_calldata);

    return ();
}

@external
@raw_input
@raw_output
func __default__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    selector: felt, calldata_size: felt, calldata: felt*
) -> (retdata_size: felt, retdata: felt*) {    
    let (current_plugin) = get_current_plugin();
    let (retdata_size: felt, retdata: felt*) = library_call(
        class_hash=current_plugin,
        function_selector=selector,
        calldata_size=calldata_size,
        calldata=calldata,
    );
    return (retdata_size=retdata_size, retdata=retdata);
}

@external
func addPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt, plugin_calldata_len: felt, plugin_calldata: felt*) {
    assert_only_self();

    with_attr error_message("PluginAccount: plugin cannot be null") {
        assert_not_zero(plugin);
    }

    initialize_plugin(plugin, plugin_calldata_len, plugin_calldata);
    _plugins.write(plugin, 1);

    return ();
}

@external
func removePlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) {
    assert_only_self();

    let (is_plugin) = _plugins.read(plugin);
    with_attr error_message("PluginAccount: unknown plugin") {
        assert_not_zero(is_plugin);
    }

    // cannot remove default plugin
    with_attr error_message("PluginAccount: cannot remove default plugin") {
        let (default_plugin) = _plugins.read(0);
        assert_not_equal(plugin, default_plugin);
    }

    _plugins.write(plugin, 0);

    return ();
}

@external
func setDefaultPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, plugin_calldata_len: felt, plugin_calldata: felt*
) {
    assert_only_self();

    with_attr error_message("PluginAccount: plugin cannot be null") {
        assert_not_zero(plugin);
    }

    let (is_plugin) = _plugins.read(plugin);
    with_attr error_message("PluginAccount: unknown plugin") {
        assert_not_zero(is_plugin);
    }

    _plugins.write(0, plugin);
    return ();
}

/////////////////////
// VIEW FUNCTIONS
/////////////////////

@view
func isValidSignature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(hash: felt, sig_len: felt, sig: felt*) -> (isValid: felt) {
    alloc_locals;
    let (default_plugin) = _plugins.read(0);

    let (calldata: felt*) = alloc();
    assert calldata[0] = hash;
    assert calldata[1] = sig_len;
    memcpy(calldata + 2, sig, sig_len);

    let (retdata_size: felt, retdata: felt*) = library_call(
        class_hash=default_plugin,
        function_selector=IS_VALID_SIGNATURE_SELECTOR,
        calldata_size=2 + sig_len,
        calldata=calldata,
    );

    assert retdata_size = 1;
    return (isValid=retdata[0]);
}

@view
func supportsInterface{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    interfaceId: felt
) -> (success: felt) {
    // 165
    if (interfaceId == 0x01ffc9a7) {
        return (TRUE,);
    }
    // IAccount
    if (interfaceId == ERC165_ACCOUNT_INTERFACE_ID) {
        return (TRUE,);
    }

    let (default_plugin) = _plugins.read(0);

    let (calldata: felt*) = alloc();
    assert calldata[0] = interfaceId;

    let (retdata_size: felt, retdata: felt*) = library_call(
        class_hash=default_plugin,
        function_selector=SUPPORTS_INTERFACE_SELECTOR,
        calldata_size=1,
        calldata=calldata,
    );

    assert retdata_size = 1;
    return (success=retdata[0]);
}

@view
func isPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) -> (
    success: felt
) {
    let (res) = _plugins.read(plugin);
    return (success=res);
}

@view
func readOnPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, selector: felt, calldata_len: felt, calldata: felt*
) -> (retdata_len: felt, retdata: felt*) {
    let (is_plugin) = _plugins.read(plugin);
    with_attr error_message("PluginAccount: unknown plugin") {
        assert_not_zero(is_plugin);
    }
    let (retdata_len: felt, retdata: felt*) = library_call(
        class_hash=plugin,
        function_selector=selector,
        calldata_size=calldata_len,
        calldata=calldata,
    );
    return (retdata_len=retdata_len, retdata=retdata);
}

@view
func getDefaultPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    plugin: felt
) {
    let (res) = _plugins.read(0);
    return (plugin=res);
}

@view
func getName() -> (name: felt) {
    return (name=NAME);
}

@view
func getVersion() -> (version: felt) {
    return (version=VERSION);
}

/////////////////////
// INTERNAL FUNCTIONS
/////////////////////

func use_plugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (plugin_id: felt) {
    alloc_locals;

    let (tx_info) = get_tx_info();
    let plugin_id = tx_info.signature[0];
    let (is_plugin) = _plugins.read(plugin_id);

    if (is_plugin == TRUE) {
        return (plugin_id=plugin_id);
    } else {
        let (default_plugin) = _plugins.read(0);
        return (plugin_id=default_plugin);
    }
}

func validate_with_plugin{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(
    plugin_id: felt,
    call_array_len: felt,
    call_array: CallArray*,
    calldata_len: felt,
    calldata: felt*,
) {
    IPlugin.library_call_validate(
        class_hash=plugin_id,
        call_array_len=call_array_len,
        call_array=call_array,
        calldata_len=calldata_len,
        calldata=calldata,
    );
    return ();
}

func execute{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(
    call_array_len: felt,
    call_array: CallArray*,
    calldata_len: felt,
    calldata: felt*,
) -> (response_len: felt, response: felt*) {
    alloc_locals;

    let (tx_info) = get_tx_info();

    /////////////// TMP /////////////////////
    // parse inputs to an array of 'Call' struct
    let (calls: Call*) = alloc();
    from_call_array_to_call(call_array_len, call_array, calldata, calls);
    let calls_len = call_array_len;
    //////////////////////////////////////////

    let (response: felt*) = alloc();
    let (response_len) = execute_list(calls_len, calls, response);
    transaction_executed.emit(
        hash=tx_info.transaction_hash, response_len=response_len, response=response
    );
    return (response_len, response);
}

func initialize_plugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, plugin_calldata_len: felt, plugin_calldata: felt*
) {
    if (plugin_calldata_len == 0) {
        return ();
    }

    library_call(
        class_hash=plugin,
        function_selector=INITIALIZE_SELECTOR,
        calldata_size=plugin_calldata_len,
        calldata=plugin_calldata,
    );

    return ();
}

func get_current_plugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    current_plugin: felt
) {
    let (current_plugin) = _current_plugin.read();
    if (current_plugin == 0) {
        let (default_plugin) = _plugins.read(0);
        return (default_plugin,);
    }
    return (current_plugin,);
}

func assert_only_self{syscall_ptr: felt*}() -> () {
    let (self) = get_contract_address();
    let (caller_address) = get_caller_address();
    with_attr error_message("PluginAccount: only self") {
        assert self = caller_address;
    }
    return ();
}

func assert_non_reentrant{syscall_ptr: felt*}() -> () {
    let (caller) = get_caller_address();
    with_attr error_message("PluginAccount: no reentrant call") {
        assert caller = 0;
    }
    return ();
}

func assert_initialized{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    let (default_plugin) = _plugins.read(0);
    with_attr error_message("PluginAccount: account not initialized") {
        assert_not_zero(default_plugin);
    }
    return ();
}

// @notice Executes a list of contract calls recursively.
// @param calls_len The number of calls to execute
// @param calls A pointer to the first call to execute
// @param response The array of felt to pupulate with the returned data
// @return response_len The size of the returned data
func execute_list{syscall_ptr: felt*}(
    calls_len: felt, calls: Call*, reponse: felt*
) -> (response_len: felt) {
    alloc_locals;

    // if no more calls
    if (calls_len == 0) {
        return (0,);
    }

    // do the current call
    let this_call: Call = [calls];
    let res = call_contract(
        contract_address=this_call.to,
        function_selector=this_call.selector,
        calldata_size=this_call.calldata_len,
        calldata=this_call.calldata,
    );

    // copy the result in response
    memcpy(reponse, res.retdata, res.retdata_size);
    // do the next calls recursively
    let (response_len) = execute_list(
        calls_len - 1, calls + Call.SIZE, reponse + res.retdata_size
    );
    return (response_len + res.retdata_size,);
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
