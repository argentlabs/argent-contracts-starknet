%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.math import assert_not_zero
from starkware.starknet.common.syscalls import (
    library_call,
    get_tx_info,
    get_contract_address,
)
from contracts.plugins.IPlugin import IPlugin
from contracts.account.library import (
    Call,
    CallArray,
    Escape,
    ArgentModel,
    from_call_array_to_call,
    execute_list,
    assert_non_reentrant,
    assert_initialized,
    assert_no_self_call,
    assert_correct_version,
    assert_only_self
)

///////////////////////
// CONSTANTS
///////////////////////

const NAME = 'ArgentPluginAccount';
const VERSION = '0.0.1';

const USE_PLUGIN_SELECTOR = 1121675007639292412441492001821602921366030142137563176027248191276862353634;

//////////////////////
// EVENTS
///////////////////////

@event
func account_created(account: felt, key: felt, guardian: felt) {
}

@event
func transaction_executed(hash: felt, response_len: felt, response: felt*) {
}

///////////////////////
// STORAGE VARIABLES
///////////////////////

@storage_var
func _plugins(plugin: felt) -> (res: felt) {
}

///////////////////////
// EXTERNAL FUNCTIONS
//////////////////////

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

    // make sure the account is initialized
    assert_initialized();

    // get the tx info
    let (tx_info) = get_tx_info();

    if (call_array_len == 1) {
        if (call_array[0].to == tx_info.account_contract_address) {
            tempvar signer_condition = (call_array[0].selector - ArgentModel.ESCAPE_GUARDIAN_SELECTOR) * (call_array[0].selector - ArgentModel.TRIGGER_ESCAPE_GUARDIAN_SELECTOR);
            tempvar guardian_condition = (call_array[0].selector - ArgentModel.ESCAPE_SIGNER_SELECTOR) * (call_array[0].selector - ArgentModel.TRIGGER_ESCAPE_SIGNER_SELECTOR);
            if (signer_condition == 0) {
                // validate signer signature
                ArgentModel.validate_signer_signature(
                    tx_info.transaction_hash, tx_info.signature_len, tx_info.signature
                );
                return ();
            }
            if (guardian_condition == 0) {
                // validate guardian signature
                ArgentModel.validate_guardian_signature(
                    tx_info.transaction_hash, tx_info.signature_len, tx_info.signature
                );
                return ();
            }
        }
    } else {
        if ((call_array[0].to - tx_info.account_contract_address) + (call_array[0].selector - USE_PLUGIN_SELECTOR) == 0) {
            validate_with_plugin(call_array_len, call_array, calldata_len, calldata);
            return ();
        } else {
            // make sure no call is to the account
            assert_no_self_call(tx_info.account_contract_address, call_array_len, call_array);
        }
    }
    // validate signer and guardian signatures
    ArgentModel.validate_signer_signature(tx_info.transaction_hash, tx_info.signature_len, tx_info.signature);
    ArgentModel.validate_guardian_signature(
        tx_info.transaction_hash, tx_info.signature_len - 2, tx_info.signature + 2
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

    // get the tx info
    let (tx_info) = get_tx_info();

    // block transaction with version != 1
    assert_correct_version(tx_info.version);

    /////////////////////// TMP /////////////////////
    // parse inputs to an array of 'Call' struct
    let (calls: Call*) = alloc();
    from_call_array_to_call(call_array_len, call_array, calldata, calls);
    let calls_len = call_array_len;
    /////////////////////////////////////////////////

    // execute calls
    let (response: felt*) = alloc();
    local response_len;
    if (calls[0].selector - USE_PLUGIN_SELECTOR == 0) {
        let (res) = execute_list(calls_len - 1, calls + Call.SIZE, response);
        assert response_len = res;
    } else {
        let (res) = execute_list(calls_len, calls, response);
        assert response_len = res;
    }
    // emit event
    transaction_executed.emit(
        hash=tx_info.transaction_hash, response_len=response_len, response=response
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
    alloc_locals;
    // get the tx info
    let (tx_info) = get_tx_info();
    // validate signatures
    ArgentModel.validate_signer_signature(tx_info.transaction_hash, tx_info.signature_len, tx_info.signature);
    ArgentModel.validate_guardian_signature(
        tx_info.transaction_hash, tx_info.signature_len - 2, tx_info.signature + 2
    );
    return ();
}

// ///////////////////// PLUGIN /////////////////////

@external
func add_plugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) {
    // only called via execute
    assert_only_self();

    // add plugin
    with_attr error_message("plugin cannot be null") {
        assert_not_zero(plugin);
    }
    _plugins.write(plugin, 1);
    return ();
}

@external
func remove_plugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) {
    // only called via execute
    assert_only_self();
    // remove plugin
    _plugins.write(plugin, 0);
    return ();
}

@external
func execute_on_plugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, selector: felt, calldata_len: felt, calldata: felt*
) {
    // only called via execute
    assert_only_self();
    // only valid plugin
    let (is_plugin) = _plugins.read(plugin);
    assert_not_zero(is_plugin);

    library_call(
        class_hash=plugin, function_selector=selector, calldata_size=calldata_len, calldata=calldata
    );
    return ();
}

@view
func is_plugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) -> (
    success: felt
) {
    let (res) = _plugins.read(plugin);
    return (success=res);
}

func validate_with_plugin{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(call_array_len: felt, call_array: CallArray*, calldata_len: felt, calldata: felt*) {
    alloc_locals;

    let plugin = calldata[call_array[0].data_offset];
    let (is_plugin) = _plugins.read(plugin);
    assert_not_zero(is_plugin);

    IPlugin.library_call_validate(
        class_hash=plugin,
        plugin_data_len=call_array[0].data_len - 1,
        plugin_data=calldata + call_array[0].data_offset + 1,
        call_array_len=call_array_len - 1,
        call_array=call_array + CallArray.SIZE,
        calldata_len=calldata_len - call_array[0].data_len,
        calldata=calldata + call_array[0].data_offset + call_array[0].data_len,
    );
    return ();
}

/////////////////////

@external
func initialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    signer: felt, guardian: felt
) {
    ArgentModel.initialize(signer, guardian);
    let (self) = get_contract_address();
    account_created.emit(account=self, key=signer, guardian=guardian);
    return ();
}

@external
func upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    implementation: felt
) {
    ArgentModel.upgrade(implementation);
    return ();
}

@external
func change_signer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_signer: felt
) {
    ArgentModel.change_signer(new_signer);
    return ();
}

@external
func change_guardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_guardian: felt
) {
    ArgentModel.change_guardian(new_guardian);
    return ();
}

@external
func change_guardian_backup{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_guardian: felt
) {
    ArgentModel.change_guardian_backup(new_guardian);
    return ();
}

@external
func trigger_escape_guardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.trigger_escape_guardian();
    return ();
}

@external
func trigger_escape_signer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.trigger_escape_signer();
    return ();
}

@external
func cancel_escape{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.cancel_escape();
    return ();
}

@external
func escape_guardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_guardian: felt
) {
    ArgentModel.escape_guardian(new_guardian);
    return ();
}

@external
func escape_signer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_signer: felt
) {
    ArgentModel.escape_signer(new_signer);
    return ();
}

/////////////////////
// VIEW FUNCTIONS
/////////////////////

@view
func is_valid_signature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(hash: felt, sig_len: felt, sig: felt*) -> (is_valid: felt) {
    let (is_valid) = ArgentModel.is_valid_signature(hash, sig_len, sig);
    return (is_valid=is_valid);
}

@view
func supportsInterface{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    interfaceId: felt
) -> (success: felt) {
    let (success) =  ArgentModel.supportsInterface(interfaceId);
    return (success=success);
}

@view
func get_signer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    signer: felt
) {
    let (res) = ArgentModel.get_signer();
    return (signer=res);
}

@view
func get_guardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    guardian: felt
) {
    let (res) = ArgentModel.get_guardian();
    return (guardian=res);
}

@view
func get_guardian_backup{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    guardian_backup: felt
) {
    let (res) = ArgentModel.get_guardian_backup();
    return (guardian_backup=res);
}

@view
func get_escape{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    active_at: felt, type: felt
) {
    let (active_at, type) = ArgentModel.get_escape();
    return (active_at=active_at, type=type);
}

@view
func get_version() -> (version: felt) {
    return (version=VERSION);
}

@view
func get_name() -> (name: felt) {
    return (name=NAME);
}
