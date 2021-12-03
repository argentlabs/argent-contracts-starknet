%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math import assert_not_zero
from starkware.starknet.common.syscalls import get_caller_address

##############################################
# User selected different single keys Guardian
##############################################

@storage_var
func _signing_key(account : felt) -> (res: felt):
end

@storage_var
func _escape_key(account : felt) -> (res: felt):
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
    
    let (account) = get_caller_address()
    if sig_len == 3:
        assert [sig + 2] = 'escape'
        let (key) = _escape_key.read(account)
        verify_ecdsa_signature(
            message=hash,
            public_key=key,
            signature_r=sig[0],
            signature_s=sig[1])
        return()
    end

    if sig_len == 2:
        let (key) = _signing_key.read(account)
        verify_ecdsa_signature(
            message=hash,
            public_key=key,
            signature_r=sig[0],
            signature_s=sig[1])
        return()
    end
    assert_not_zero(0)
    return()
end

@view
func weight() -> (weight: felt):
    return (weight=1)
end

@external
func set_signing_key{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        key: felt
    ) -> ():
    let (account) = get_caller_address()
    _signing_key.write(account, key)
    return()
end

@external
func set_escape_key{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        key: felt
    ) -> ():
    let (account) = get_caller_address()
    _escape_key.write(account, key)
    return()
end

@view
func get_signing_key{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (account: felt) -> (signing_key: felt):
    let (signing_key) = _signing_key.read(account)
    return (signing_key=signing_key)
end

@view
func get_escape_key{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (account: felt) -> (escape_key: felt):
    let (escape_key) = _escape_key.read(account)
    return (escape_key=escape_key)
end