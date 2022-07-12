%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash_state import (
    HashState, hash_finalize, hash_init, hash_update, hash_update_single)
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_zero, assert_nn
from starkware.starknet.common.syscalls import (
    call_contract, get_tx_info, get_contract_address, get_caller_address, get_block_timestamp
)

@contract_interface
namespace IAccount:
    func is_valid_signature(hash: felt, sig_len: felt, sig: felt*):
    end
end

struct CallArray:
    member to: felt
    member selector: felt
    member data_offset: felt
    member data_len: felt
end

@storage_var
func SessionKey_revoked_keys(key: felt) -> (res: felt):
end

@external
func validate{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        plugin_data_len: felt,
        plugin_data: felt*,
        call_array_len: felt,
        call_array: CallArray*,
        calldata_len: felt,
        calldata: felt*
    ):
    alloc_locals
    
    # get the tx info
    let (tx_info) = get_tx_info()

    # check is the session has expired
    let session_expires = [plugin_data + 1]
    with_attr error_message("session expired"):
        let (now) = get_block_timestamp()
        assert_nn(session_expires - now)
    end
    # check if the session is approved
    let session_key = [plugin_data]
    let (hash) = compute_hash(session_key, session_expires)
    with_attr error_message("unauthorised session"):
        IAccount.is_valid_signature(
            contract_address=tx_info.account_contract_address,
            hash=hash,
            sig_len=plugin_data_len - 2,
            sig=plugin_data + 2
        )
    end
    # check if the session key is revoked
    with_attr error_message("session key revoked"):
        let (is_revoked) = SessionKey_revoked_keys.read(session_key)
        assert is_revoked = 0
    end
    # check if the tx is signed by the session key
    with_attr error_message("session key signature invalid"):
        verify_ecdsa_signature(
            message=tx_info.transaction_hash,
            public_key=session_key,
            signature_r=tx_info.signature[0],
            signature_s=tx_info.signature[1]
        )
    end
    return()
end

@external
func revoke_session_key{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        session_key: felt
    ):
    SessionKey_revoked_keys.write(session_key, 1)
    return()
end

func compute_hash{pedersen_ptr: HashBuiltin*}(session_key: felt, session_expires: felt) -> (hash : felt):
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, session_key)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, session_expires)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
    end
    return (hash=res)
end
