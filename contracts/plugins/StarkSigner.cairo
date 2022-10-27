%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.signature import verify_ecdsa_signature
from contracts.account.library import CallArray
from starkware.starknet.common.syscalls import (
    get_tx_info,
    get_contract_address,
    get_caller_address,
)

@storage_var
func StarkSigner_public_key() -> (res: felt) {
}

@external
func initialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(plugin_data_len: felt, plugin_data: felt*) {
    let (is_initialized) = StarkSigner_public_key.read();
    with_attr error_message("StarkSigner: already initialized") {
        assert is_initialized = 0;
    }
    with_attr error_message("StarkSigner: initialise failed") {
        assert plugin_data_len = 1;
    }
    StarkSigner_public_key.write(plugin_data[0]);
    return ();
}

@external
func setPublicKey{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    public_key: felt
) {
    assert_only_self();

    with_attr error_message("StarkSigner: public key can not be zero") {
        assert_not_zero(public_key);
    }
    StarkSigner_public_key.write(public_key);
    return ();
}

@view
func getPublicKey{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    public_key: felt
) {
    let (public_key) = StarkSigner_public_key.read();
    return (public_key=public_key);
}


@view
func supportsInterface{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    interfaceId: felt
) -> (success: felt) {
    // 165
    if (interfaceId == 0x01ffc9a7) {
        return (TRUE,);
    }
    return (FALSE,);
}

@view
func validate{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(
    call_array_len: felt,
    call_array: CallArray*,
    calldata_len: felt,
    calldata: felt*,
) {
    alloc_locals;
    let (tx_info) = get_tx_info();
    is_valid_signature(tx_info.transaction_hash, tx_info.signature_len, tx_info.signature);
    return ();
}

@view
func is_valid_signature{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*
}(
    hash: felt,
    signature_len: felt,
    signature: felt*
) -> (is_valid: felt) {

    with_attr error_message("StarkSigner: invalid signature length") {
        assert signature_len = 3;
    }
    
    let (public_key) = StarkSigner_public_key.read();

    let sig_r = signature[1];
    let sig_s = signature[2];

    verify_ecdsa_signature(
        message=hash,
        public_key=public_key,
        signature_r=sig_r,
        signature_s=sig_s
    );

    return (is_valid=TRUE);
}

func assert_only_self{syscall_ptr: felt*}() -> () {
    let (self) = get_contract_address();
    let (caller_address) = get_caller_address();
    with_attr error_message("StarkSigner: only self") {
        assert self = caller_address;
    }
    return ();
}
