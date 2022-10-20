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
    assert_initialized,
    assert_no_self_call,
)


@external
func initialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(data_len: felt, data: felt*) {
    // assert data_len == 2;
    let signer = data[0];
    let guardian = data[1];
    ArgentModel.initialize(signer, guardian);
    return ();
}

@view
func isValidSignature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(hash: felt, signature_len: felt, signature: felt*) -> (isValid: felt) {
    let (isValid) = is_valid_signature(hash, signature_len, signature);
    return (isValid=isValid);
}

@view
func is_valid_signature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(hash: felt, signature_len: felt, signature: felt*) -> (isValid: felt) {
    let (isValid) = ArgentModel.is_valid_signature(hash, signature_len, signature);
    return (isValid=isValid);
}

@external
func validate{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr}(
    call_array_len: felt,
    call_array: CallArray*,
    calldata_len: felt,
    calldata: felt*,
) {
    alloc_locals;
    let (tx_info) = get_tx_info();
    // invokeOnPlugin??
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
        }
    }
    // validate signer and guardian signatures
    isValidSignature(tx_info.transaction_hash, tx_info.signature_len, tx_info.signature);
    return ();
}


// BIG TODO this is publicly callable now if we expose it via __default__ is so, we need to check the call comes from the wallet!
@external
func changeSigner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newSigner: felt
) {
    ArgentModel.change_signer(newSigner);
    return ();
}


@external
func changeGuardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newGuardian: felt
) {
    ArgentModel.change_guardian(newGuardian);
    return ();
}

@external
func changeGuardianBackup{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newGuardian: felt
) {
    ArgentModel.change_guardian_backup(newGuardian);
    return ();
}


@external
func triggerEscapeGuardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.trigger_escape_guardian();
    return ();
}

@external
func triggerEscapeSigner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.trigger_escape_signer();
    return ();
}

@external
func cancelEscape{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    ArgentModel.cancel_escape();
    return ();
}

@external
func escapeGuardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newGuardian: felt
) {
    ArgentModel.escape_guardian(newGuardian);
    return ();
}

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

@view
func getSigner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    signer: felt
) {
    let (res) = ArgentModel.get_signer();
    return (signer=res);
}

@view
func getGuardian{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    guardian: felt
) {
    let (res) = ArgentModel.get_guardian();
    return (guardian=res);
}

@view
func getGuardianBackup{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    guardianBackup: felt
) {
    let (res) = ArgentModel.get_guardian_backup();
    return (guardianBackup=res);
}

@view
func getEscape{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    activeAt: felt, type: felt
) {
    let (activeAt, type) = ArgentModel.get_escape();
    return (activeAt=activeAt, type=type);
}
