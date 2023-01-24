%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, EcOpBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_zero
from starkware.starknet.common.syscalls import (
    library_call,
    get_tx_info,
    get_contract_address,
)
from contracts.plugins.IPlugin import IPlugin
from contracts.utils.calls import (
    CallArray,
    execute_multicall,
)
from contracts.account.library import (
    ArgentModel,
    assert_non_reentrant,
    assert_initialized,
    assert_no_self_call,
    assert_correct_tx_version,
    assert_only_self
)

//
// @title ArgentPluginAccount
// @author Argent Labs
// @notice Experimental Argent account supporting plugins
//

///////////////////////
// CONSTANTS
///////////////////////

const NAME = 'ArgentPluginAccount';
const VERSION = '0.0.3';

// get_selector_from_name('use_plugin')
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
// ACCOUNT INTERFACE
//////////////////////

@external
func __validate__{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    ec_op_ptr: EcOpBuiltin*,
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
            // a * b == 0 --> a == 0 OR b == 0
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
            with_attr error_message("argent: forbidden call") {
                assert_not_zero(call_array[0].selector - ArgentModel.EXECUTE_AFTER_UPGRADE_SELECTOR);
            } 
        }
    } else {
        if (call_array[0].to == tx_info.account_contract_address and call_array[0].selector == USE_PLUGIN_SELECTOR) {
            // make sure the remaining calls are not to the account
            assert_no_self_call(tx_info.account_contract_address, call_array_len - 1, call_array + CallArray.SIZE);
            // validate with the plugin
            validate_with_plugin(call_array_len, call_array, calldata_len, calldata);
            return ();
        }
        // make sure no call is to the account
        assert_no_self_call(tx_info.account_contract_address, call_array_len, call_array);
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

    let (tx_info) = get_tx_info();
    
    // block transaction with version != 1 or QUERY
    assert_correct_tx_version(tx_info.version);

    // no reentrant call to prevent signature reutilization
    assert_non_reentrant();

    let (retdata_len, retdata) = execute_multicall_plugin(call_array_len, call_array, calldata);

    // emit event
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
    ec_op_ptr: EcOpBuiltin*,
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

@raw_input
@external
func __validate_deploy__{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    ec_op_ptr: EcOpBuiltin*,
    range_check_ptr
} (selector: felt, calldata_size: felt, calldata: felt*) {
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

@view
func isValidSignature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ec_op_ptr: EcOpBuiltin*, range_check_ptr
}(hash: felt, sig_len: felt, sig: felt*) -> (is_valid: felt) {
    let (is_valid) = ArgentModel.is_valid_signature(hash, sig_len, sig);
    return (is_valid=is_valid);
}

@view
func supportsInterface{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    interfaceId: felt
) -> (success: felt) {
    let (success) =  ArgentModel.supports_interface(interfaceId);
    return (success=success);
}

///////////////////////
// PLUGIN
//////////////////////

// @dev Adds a new plugin.
// Must be called via {__execute__} and authorised by the signer and a guardian.
// @param plugin The class hash of the plugin
@external
func addPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) {
    // only called via execute
    assert_only_self();

    // add plugin
    with_attr error_message("argent: plugin invalid") {
        assert_not_zero(plugin);
    }
    _plugins.write(plugin, 1);
    return ();
}

// @dev Removes an existing plugin.
// Must be called via {__execute__} and authorised by the signer and a guardian.
// @param plugin The class hash of the plugin
@external
func removePlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) {
    // only called via execute
    assert_only_self();

    let (is_plugin) = _plugins.read(plugin);
    with_attr error_message("argent: unknown plugin") {
        assert_not_zero(is_plugin);
    }
    // remove plugin
    _plugins.write(plugin, 0);
    return ();
}

// @dev Executes a library call on one of the enabled plugin of the account.
// Must be called via {__execute__} and authorised by the signer and a guardian.
// @param plugin The class hash of the plugin
// @param selector The method to execute on the plugin
// @param calldata The call data of the call
@external
func executeOnPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin: felt, selector: felt, calldata_len: felt, calldata: felt*
) {
    // only called via execute
    assert_only_self();

    let (is_plugin) = _plugins.read(plugin);
    with_attr error_message("argent: unknown plugin") {
        assert_not_zero(is_plugin);
    }

    library_call(
        class_hash=plugin, function_selector=selector, calldata_size=calldata_len, calldata=calldata
    );
    return ();
}

// @dev Checks if a plugin is enabled on the account.
// @param plugin The class hash of the plugin
// @return success True if the plugin is enabled
@view
func isPlugin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin: felt) -> (
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
    with_attr error_message("argent: unknown plugin") {
        assert_not_zero(is_plugin);
    }

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

///////////////////////
// EXTERNAL FUNCTIONS
//////////////////////

// @dev Initialises the account with the signer and an optional guardian.
// Must be called immediately after the account is deployed.
// @param signer The signer public key
// @param guardian The guardian public key
@external
func initialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    signer: felt, guardian: felt
) {
    ArgentModel.initialize(signer, guardian);
    let (self) = get_contract_address();
    account_created.emit(account=self, key=signer, guardian=guardian);
    return ();
}

// @dev Upgrades the implementation of the account and delegate calls {execute_after_upgrade} if additional data is provided.
// Must be called via {__execute__} and authorised by the signer and a guardian. 
// @param implementation The class hash of the new implementation
// @param calldata The calldata to pass to {execute_after_upgrade}
// @return retdata The return of the library call to {execute_after_upgrade}
@external
func upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    implementation: felt, calldata_len: felt, calldata: felt*
) -> (retdata_len: felt, retdata: felt*) {
    alloc_locals;
    // upgrades the implementation
    ArgentModel.upgrade(implementation);
    // library call to implementation.execute_after_upgrade
    let (retdata_size: felt, retdata: felt*) = library_call(
        class_hash=implementation,
        function_selector=ArgentModel.EXECUTE_AFTER_UPGRADE_SELECTOR,
        calldata_size=calldata_len,
        calldata=calldata,
    );
    return (retdata_len=retdata_size, retdata=retdata);
}

// @dev Logic or multicall to execute after an upgrade.
// Can only be called by the account after a call to {upgrade}.
// @param call_array The multicall to execute
// @param calldata The calldata associated to the multicall
// @return retdata An array containing the output of the calls
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
    let (retdata_len, retdata) = execute_multicall(call_array_len, call_array, calldata);
    return (retdata_len=retdata_len, retdata=retdata);
}

// @dev Changes the signer.
// Must be called via {__execute__} and authorised by the signer and a guardian.
// @param newSigner The public key of the new signer
@external
func changeSigner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newSigner: felt
) {
    ArgentModel.change_signer(newSigner);
    return ();
}

// @dev Changes the guardian.
// Must be called via {__execute__} and authorised by the signer and a guardian.
// @param newGuardian The public key of the new guardian
@external
func changeGuardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newGuardian: felt
) {
    ArgentModel.change_guardian(newGuardian);
    return ();
}

// @dev Changes the guardian backup.
// Must be called via {__execute__} and authorised by the signer and a guardian.
// @param newGuardian The public key of the new guardian backup
@external
func changeGuardianBackup{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newGuardian: felt
) {
    ArgentModel.change_guardian_backup(newGuardian);
    return ();
}

// @dev Triggers the escape of the guardian when it is lost or compromised.
// Must be called via {__execute__} and authorised by the signer alone.
// Can override an ongoing escape of the signer.
@external
func triggerEscapeGuardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.trigger_escape_guardian();
    return ();
}

// @dev Triggers the escape of the signer when it is lost or compromised.
// Must be called via {__execute__} and authorised by a guardian alone.
// Cannot override an ongoing escape of the guardian.
@external
func triggerEscapeSigner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.trigger_escape_signer();
    return ();
}

// @dev Cancels an ongoing escape if any.
// Must be called via {__execute__} and authorised by the signer and a guardian.
@external
func cancelEscape{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.cancel_escape();
    return ();
}

// @dev Escapes the guardian after the escape period of 7 days.
// Must be called via {__execute__} and authorised by the signer alone.
// @param newGuardian The public key of the new guardian
@external
func escapeGuardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newGuardian: felt
) {
    ArgentModel.escape_guardian(newGuardian);
    return ();
}

// @dev Escapes the signer after the escape period of 7 days.
// Must be called via {__execute__} and authorised by a guardian alone.
// @param newSigner The public key of the new signer
@external
func escapeSigner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newSigner: felt
) {
    ArgentModel.escape_signer(newSigner);
    return ();
}

/////////////////////
// VIEW FUNCTIONS
/////////////////////

// @dev Gets the current signer
// @return signer The public key of the signer
@view
func getSigner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    signer: felt
) {
    let (res) = ArgentModel.get_signer();
    return (signer=res);
}

// @dev Gets the current guardian
// @return guardian The public key of the guardian
@view
func getGuardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    guardian: felt
) {
    let (res) = ArgentModel.get_guardian();
    return (guardian=res);
}

// @dev Gets the current guardian backup
// @return guardian The public key of the guardian backup
@view
func getGuardianBackup{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    guardianBackup: felt
) {
    let (res) = ArgentModel.get_guardian_backup();
    return (guardianBackup=res);
}

// @dev Gets the details of the ongoing escape
// @return activeAt The timestamp at which the escape can be executed
// @return type The type of the ongoing escape: 0=no escape, 1=guardian escape, 2=signer escape
@view
func getEscape{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    activeAt: felt, type: felt
) {
    let (activeAt, type) = ArgentModel.get_escape();
    return (activeAt=activeAt, type=type);
}

// @dev Gets the version of the account implementation
// @return version The current version as a short string
@view
func getVersion() -> (version: felt) {
    return (version=VERSION);
}

// @dev Gets the name of the account implementation
// @return name The name as a short string
@view
func getName() -> (name: felt) {
    return (name=NAME);
}

// @dev DEPRECATED: Remove when isValidSignature() is widely used
@view
func is_valid_signature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ec_op_ptr: EcOpBuiltin*, range_check_ptr
}(hash: felt, sig_len: felt, sig: felt*) -> (is_valid: felt) {
    let (is_valid) = ArgentModel.is_valid_signature(hash, sig_len, sig);
    return (is_valid=is_valid);
}

func execute_multicall_plugin{syscall_ptr: felt*}(
    call_array_len: felt, call_array: CallArray*, calldata: felt*
) -> (retdata_len: felt, retdata: felt*) {
    alloc_locals;

    if (call_array[0].selector == USE_PLUGIN_SELECTOR) {
        let (response_len, response) = execute_multicall(call_array_len - 1, call_array + CallArray.SIZE, calldata);
        return (retdata_len=response_len, retdata=response);
    } else {
        let (response_len, response) = execute_multicall(call_array_len, call_array, calldata);
        return (retdata_len=response_len, retdata=response);
    }
}
