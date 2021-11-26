%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_not_zero, assert_nn
from starkware.starknet.common.syscalls import get_tx_signature

######################################
# Single Common Stark Key Guardian
######################################

@storage_var
func _signing_key() -> (res: felt):
end

@constructor
func constructor{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        signing_key: felt
    ):
    assert_not_zero(signing_key)
    _signing_key.write(signing_key)
    return ()
end

@external
func set_signing_key{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        new_signing_key: felt
    ) -> ():

    # get the signature
    let (sig_len : felt, sig : felt*) = get_tx_signature()
    # Verify the signature length.
    assert_nn(sig_len - 2)
    # Compute the hash of the message.
    let (hash) = hash2{hash_ptr=pedersen_ptr}(new_signing_key, 0)
    # get the existing signing key
    let (signing_key) = _signing_key.read()
    # verify the signature
    verify_ecdsa_signature(
        message=hash,
        public_key=signing_key,
        signature_r=sig[0],
        signature_s=sig[1])
    # set the new key
    _signing_key.write(new_signing_key)
    return()
end

@view
func is_valid_signature{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        hash: felt,
        sig_len: felt,
        sig: felt*
    ) -> ():
    assert_nn(sig_len - 2)
    let (signing_key) = _signing_key.read()
    verify_ecdsa_signature(
        message=hash,
        public_key=signing_key,
        signature_r=sig[0],
        signature_s=sig[1])
    return()
end

@view
func weight() -> (weight: felt):
    return (weight=1)
end

@view
func get_signing_key{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } () -> (signing_key: felt):
    let (signing_key) = _signing_key.read()
    return (signing_key=signing_key)
end