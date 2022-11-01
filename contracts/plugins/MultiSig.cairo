%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, assert_nn, assert_lt_felt
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.starknet.common.syscalls import (
    get_tx_info,
    get_contract_address,
    get_caller_address,
)

from contracts.account.library import (
    Call,
    CallArray,
    assert_only_self,
    assert_self_or_zero
)


@storage_var
func MultiSig_threshold() -> (res: felt) {
}

@storage_var
func MultiSig_owners_len() -> (res: felt) {
}

@storage_var
func MultiSig_owners(address: felt) -> (res: felt) {
}

// CHECK think about nonces
// CHECK think about other account as a member
// CHECK think revoking signature
// CHECK should it be an easy way to list owners?

@external
func initialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin_data_len: felt, plugin_data: felt*
) {
    alloc_locals;

    assert_self_or_zero();

    let (threshold) = MultiSig_threshold.read();
    with_attr error_message("MultiSig: already initialized") {
        assert threshold = FALSE;
    }

    let threshold: felt  = plugin_data[0];
    let owners_len: felt = plugin_data[1];
    let owners: felt* = plugin_data + 2;

    with_attr error_message("MultiSig: Zero threshold") {
        assert_nn(threshold);
    }

    with_attr error_message("MultiSig: Zero owners") {
        assert_nn(owners_len);
    }

    with_attr error_message("MultiSig: Bad threshold") {
        assert_le(threshold, owners_len);
    }

    // CHECK MAX_OWNERS?

    _add_owners(owners_len, owners);
    MultiSig_owners_len.write(owners_len);
    MultiSig_threshold.write(threshold);    
    return ();
}

@external
func add_owners{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_threshold: felt, new_owners_len: felt, new_owners: felt*
) {
    assert_only_self();
    let (threshold) = MultiSig_threshold.read();
    with_attr error_message("MultiSig: not initialized") {
        assert_nn(threshold);
    }

    with_attr error_message("MultiSig: Zero threshold") {
        assert_nn(new_threshold);
    }

    // CHECK MAX_OWNERS?

    _add_owners(new_owners_len, new_owners);
    let (current_owners_len) = MultiSig_owners_len.read();
    MultiSig_owners_len.write(current_owners_len + new_owners_len);

    let (new_owners_len) = MultiSig_owners_len.read();
    with_attr error_message("MultiSig: Bad threshold") {
        assert_le(new_threshold, new_owners_len);
    }

    MultiSig_threshold.write(new_threshold);  
    return ();
}

func _add_owners{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owners_len: felt, owners: felt*
) {
    if (owners_len == 0) {
        return ();
    }
    let owner = owners[0];
    let (current_owner_status) = MultiSig_owners.read(owner);
    with_attr error_message("MultiSig: Already an owner: {owner}") {
        assert current_owner_status = FALSE;
    }
    MultiSig_owners.write(owner, TRUE);

    _add_owners(owners_len - 1, owners + 1);
    return ();
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

    let (threshold) = MultiSig_threshold.read();
    with_attr error_message("MultiSig: not initialized") {
        assert_nn(threshold);
    }

    let signatures = signature[1];

    with_attr error_message("MultiSig: Invalid signature length") {
        assert signature_len = 2 + (3 * signatures);
    }

    with_attr error_message("MultiSig: Not enough (or too many) signatures") {
        // CHECK allow extra sigs? why?
        assert threshold = signatures;
    }

    require_signatures(
        hash=hash,
        last_owner=0,
        signatures_len=signatures,
        signatures=signature + 2
    );
    return (is_valid=TRUE);
}

func require_signatures{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*
}(
    hash: felt,
    last_owner: felt,
    signatures_len: felt,
    signatures: felt*
) {
    if (signatures_len == 0){
        return ();
    }

    let owner = signatures[0];
    let sig_r = signatures[1];
    let sig_s = signatures[2];

    let (is_owner) = MultiSig_owners.read(address=owner);
    with_attr error_message("MultiSig: {owner} is not an owner") {
        assert is_owner = TRUE;
    }

    with_attr error_message("MultiSig: Signatures are not sorted") {
        // owner > last_owner . This guarantees unique owners. Signatures need to be ordered by owner
        assert_lt_felt(last_owner, owner);
    }

    // CHECK maybe get the owner from the signature, not sure if cheaper
    verify_ecdsa_signature(
        message=hash,
        public_key=owner,
        signature_r=sig_r,
        signature_s=sig_s
    );
    require_signatures(
        hash=hash,
        last_owner=owner,
        signatures_len=signatures_len - 1,
        signatures=signatures + 3
    );
    return ();
}


@view
func is_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    address: felt
) -> (is_owner: felt) {
    let (is_owner) = MultiSig_owners.read(address=address);
    return (is_owner,);
}

@view
func get_threshold{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (threshold: felt) {
    let (threshold) = MultiSig_threshold.read();
    return (threshold,);
}
