%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_nn, assert_not_equal
from starkware.starknet.common.syscalls import (
    get_tx_info,
    library_call,
    get_contract_address,
)
from starkware.cairo.common.bool import TRUE, FALSE
from contracts.account.library import (
    Call,
    CallArray,
    Escape,
    ArgentModel,
    execute_call_array,
    assert_only_self,
    assert_correct_tx_version,
    assert_non_reentrant,
    assert_no_self_call,
)
from contracts.plugins.IPlugin import IPlugin

/////////////////////
// CONSTANTS
/////////////////////

const NAME = 'ArgentPluginAccount';
const VERSION = '0.0.1';


/////////////////////
// EVENTS
/////////////////////

// @event
// func account_created(account: felt, key: felt, guardian: felt) {
// }
@event
func account_created(account: felt) {
}

@event
func transaction_executed(hash: felt, response_len: felt, response: felt*) {
}

/////////////////////
// STORAGE VARIABLES
/////////////////////

@storage_var
func _plugins(plugin: felt) -> (res: felt) {
}

@storage_var
func _initialized() -> (res: felt) {
}

/////////////////////
// ACCOUNT INTERFACE
/////////////////////


@external
func __validate__{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    range_check_ptr
} (
    call_array_len: felt,
    call_array: CallArray*,
    calldata_len: felt,
    calldata: felt*
) {
    alloc_locals;

    assert_initialized();

    let (tx_info) = get_tx_info();

    // block transaction with version != 1 or QUERY
    assert_correct_tx_version(tx_info.version);

    if (call_array_len == 1) {
        if (call_array[0].to == tx_info.account_contract_address) {
            with_attr error_message("argent: forbidden call") {
                assert_not_zero(call_array[0].selector - ArgentModel.EXECUTE_AFTER_UPGRADE_SELECTOR);
            }
        }
    } else {
        // make sure no call is to the account
        assert_no_self_call(tx_info.account_contract_address, call_array_len, call_array);
    }

    let (plugin) = get_plugin_from_signature(tx_info.signature_len, tx_info.signature);

    IPlugin.library_call_validate(
        class_hash=plugin,
        call_array_len=call_array_len,
        call_array=call_array,
        calldata_len=calldata_len,
        calldata=calldata,
    );
    return ();
}

@external
@raw_output
func __execute__{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    range_check_ptr
} (
    call_array_len: felt,
    call_array: CallArray*,
    calldata_len: felt,
    calldata: felt*
) -> (
    retdata_size: felt, retdata: felt*
) {
    alloc_locals;
    
    // no reentrant call to prevent signature reutilization
    assert_non_reentrant();

    // execute calls
    let (retdata_len, retdata) = execute_call_array(call_array_len, call_array, calldata_len, calldata);

    // emit event
    let (tx_info) = get_tx_info();
    transaction_executed.emit(
        hash=tx_info.transaction_hash, response_len=retdata_len, response=retdata
    );
    return (retdata_size=retdata_len, retdata=retdata);
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


@raw_input
@external
func __validate_deploy__{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    range_check_ptr
} (selector: felt, calldata_size: felt, calldata: felt*) {
    alloc_locals;
    assert_initialized();
    let (tx_info) = get_tx_info();
    let (is_valid) = isValidSignature(tx_info.transaction_hash, tx_info.signature_len, tx_info.signature);
    with_attr error_message("PluginAccount: invalid deploy") {
        assert_not_zero(is_valid);
    }
    return ();
}


@view
func isValidSignature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(hash: felt, sig_len: felt, sig: felt*) -> (isValid: felt) {
    alloc_locals;

    let (plugin) = get_plugin_from_signature(sig_len, sig);

    let (isValid) = IPlugin.library_call_is_valid_signature(
        class_hash=plugin,
        hash=hash,
        sig_len=sig_len,
        sig=sig
    );

    return (isValid=isValid);
}


@view
func supportsInterface{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    interfaceId: felt
) -> (success: felt) {
    let (success) =  ArgentModel.supports_interface(interfaceId);
    return (success=success);
}


/////////////////////
// EXTERNAL FUNCTIONS
/////////////////////


@external
func initialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, plugin_calldata_len: felt, plugin_calldata: felt*
) {
    let (initialized) = _initialized.read();
    with_attr error_message("PluginAccount: already initialized") {
        assert initialized = 0;
    }

    with_attr error_message("PluginAccount: plugin cannot be null") {
        assert_not_zero(plugin);
    }

    _plugins.write(plugin, 1);
    _initialized.write(1);

    initialize_plugin(plugin, plugin_calldata_len, plugin_calldata);

    let (self) = get_contract_address();
    account_created.emit(self);

    return ();
}

@external
func upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    implementation: felt, calldata_len: felt, calldata: felt*
) -> (retdata_len: felt, retdata: felt*) {
    ArgentModel.upgrade(implementation);

    if (calldata_len == 0) {
        let (retdata: felt*) = alloc();
        return (retdata_len=0, retdata=retdata);
    } else {
        let (retdata_size: felt, retdata: felt*) = library_call(
            class_hash=implementation,
            function_selector=ArgentModel.EXECUTE_AFTER_UPGRADE_SELECTOR,
            calldata_size=calldata_len,
            calldata=calldata,
        );
        return (retdata_len=retdata_size, retdata=retdata);
    }
}

@external
func execute_after_upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    call_array_len: felt, call_array: CallArray*, calldata_len: felt, calldata: felt*
) -> (retdata_len: felt, retdata: felt*) {
    alloc_locals;
    // only self
    assert_only_self();
    // only calls to external contract
    let (self) = get_contract_address();
    assert_no_self_call(self, call_array_len, call_array);
    // execute calls
    let (retdata_len, retdata) = execute_call_array(call_array_len, call_array, calldata_len, calldata);
    return (retdata_len=retdata_len, retdata=retdata);
}


@view
func getVersion() -> (version: felt) {
    return (version=VERSION);
}

@view
func getName() -> (name: felt) {
    return (name=NAME);
}

// TMP: Remove when isValidSignature() is widely used 
@view
func is_valid_signature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(hash: felt, sig_len: felt, sig: felt*) -> (is_valid: felt) {
    let (is_valid) = isValidSignature(hash, sig_len, sig);
    return (is_valid=is_valid);
}

func assert_initialized{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    let (initialized) = _initialized.read();
    with_attr error_message("PluginAccount: account not initialized") {
        assert_not_zero(initialized);
    }
    return ();
}

@view
func get_plugin_from_signature{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    signature_len: felt, signature: felt*,
) -> (plugin: felt) {
    alloc_locals;

    with_attr error_message("PluginAccount: invalid signature") {
        assert_not_zero(signature_len);
    }

    let plugin = signature[0];

    let (is_plugin) = _plugins.read(plugin);
    with_attr error_message("PluginAccount: unregistered plugin") {
        assert_not_zero(is_plugin);
    }
    return (plugin=plugin);
}

func initialize_plugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, plugin_calldata_len: felt, plugin_calldata: felt*
) {
    if (plugin_calldata_len == 0) {
        return ();
    }

    IPlugin.library_call_initialize(
        class_hash=plugin,
        data_len=plugin_calldata_len,
        data=plugin_calldata,
    );

    return ();
}

@external
func addPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt, plugin_calldata_len: felt, plugin_calldata: felt*) {
    assert_only_self();

    with_attr error_message("PluginAccount: plugin cannot be null") {
        assert_not_zero(plugin);
    }

    let (is_plugin) = _plugins.read(plugin);
    with_attr error_message("PluginAccount: plugin already registered") {
        assert is_plugin = 0;
    }

    _plugins.write(plugin, 1);

    initialize_plugin(plugin, plugin_calldata_len, plugin_calldata);

    return ();
}

@external
func removePlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) {
    assert_only_self();

    let (is_plugin) = _plugins.read(plugin);
    with_attr error_message("PluginAccount: unknown plugin") {
        assert_not_zero(is_plugin);
    }

    let (tx_info) = get_tx_info();

    let (signature_plugin) = get_plugin_from_signature(tx_info.signature_len, tx_info.signature);
    with_attr error_message("PluginAccount: plugin can't remove itself") {
        assert_not_equal(signature_plugin, plugin);
    }

    _plugins.write(plugin, 0);
    return ();
}

@external
func executeOnPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, selector: felt, calldata_len: felt, calldata: felt*
) -> (retdata_len: felt, retdata: felt*) {

    // only valid plugin
    let (is_plugin) = _plugins.read(plugin);
    assert_not_zero(is_plugin);

    let (retdata_len: felt, retdata: felt*) = library_call(
        class_hash=plugin,
        function_selector=selector,
        calldata_size=calldata_len,
        calldata=calldata,
    );
    return (retdata_len=retdata_len, retdata=retdata);
}

@view
func isPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) -> (
    success: felt
) {
    let (res) = _plugins.read(plugin);
    return (success=res);
}

