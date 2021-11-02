%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math import assert_not_zero

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
    assert sig_len = 2
    let (signing_key) = _signing_key.read()
    verify_ecdsa_signature(
        message=hash,
        public_key=signing_key,
        signature_r=sig[0],
        signature_s=sig[1])
    return()
end