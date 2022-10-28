%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_not_zero
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
    assert_only_self
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

// TODO think about nonces
// TODO think other account as a member

@external
func initialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    plugin_data_len: felt, plugin_data: felt*
) {
    alloc_locals;

    let (threshold) = MultiSig_threshold.read();
    with_attr error_message("MultiSig: already initialized") {
        assert threshold = 0;
    }

    let threshold = plugin_data[0];
    let owners_len = plugin_data[1];
    let owners = plugin_data + 2;

    with_attr error_message("MultiSig: invalid threshold") {
        assert_not_zero(threshold);
    }

    // require(_owners.length > 0 && _owners.length <= MAX_OWNER_COUNT, "MSW: Not enough or too many owners");
    with_attr error_message("MultiSig: XXX") {
        assert_not_zero(owners_len);
    }

    add_owners(owners_len, owners);

    //require(_threshold > 0 && _threshold <= _owners.length, "MSW: Invalid threshold");
    MultiSig_threshold.write(threshold);    
    return ();
}


func add_owners{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owners_len: felt, owners: felt*
) {
    if (owners_len == 0) {
        return ();
    }
    let owner = owners[0];
    let (current_owner_status) = MultiSig_owners.read(owner);
    with_attr error_message("MultiSig: Already an owner") {
        assert current_owner_status = FALSE;
    }
    let (current_owners_len) = MultiSig_owners_len.read();
    MultiSig_owners_len.write(current_owners_len + 1);
    MultiSig_owners.write(owner, TRUE);
    add_owners(owners_len - 1, owners + 1);
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

    // TODO threshold
    // TODO signature_lenght
    // TODO make sure sigs are all different
    let (threshold) = MultiSig_threshold.read();

    let signatures = signature[1];
    require_signatures(hash, signatures, signature + 2);
    return (is_valid=TRUE);
}

func require_signatures{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*
}(
    hash: felt,
    signatures_len: felt,
    signatures: felt*
) {
    if (signatures_len == 0){
        return ();
    }

    let owner = signatures[0];
    let sig_r = signatures[1];
    let sig_s = signatures[2];

    // TODO assert that owner is really an owner
    // TODO maybe get the owner from the signature, not sure if cheaper

    verify_ecdsa_signature(
        message=hash,
        public_key=owner,
        signature_r=sig_r,
        signature_s=sig_s
    );
    require_signatures(hash, signatures_len - 1, signatures + 3);
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