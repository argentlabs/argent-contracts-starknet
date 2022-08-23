%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash_state import (
    HashState, hash_finalize, hash_init, hash_update, hash_update_single)
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_not_zero, assert_nn
from starkware.starknet.common.syscalls import (
    call_contract, get_tx_info, get_contract_address, get_caller_address, get_block_timestamp
)

# H('StarkNetDomain(chainId:felt)')
const STARKNET_DOMAIN_TYPE_HASH = 0x13cda234a04d66db62c06b8e3ad5f91bd0c67286c2c7519a826cf49da6ba478
# H('Session(key:felt,expires:felt,root:merkletree)')
const SESSION_TYPE_HASH = 0x1aa0e1c56b45cf06a54534fa1707c54e520b842feb21d03b7deddb6f1e340c
# H(Policy(contractAddress:felt,selector:selector))
const POLICY_TYPE_HASH = 0x2f0026e78543f036f33e26a8f5891b88c58dc1e20cbbfaf0bb53274da6fa568

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

@event
func session_key_revoked(session_key: felt):
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

    # parse the plugin data
    let session_key = [plugin_data]
    let session_expires = [plugin_data + 1]
    let root = [plugin_data + 2]
    let proof_len = [plugin_data + 3]
    let proofs_len = proof_len * call_array_len
    let proofs = plugin_data + 4
    let session_token_len = plugin_data_len - 4 - proofs_len
    let session_token = plugin_data + 4 + proofs_len

    # check if the session has expired
    with_attr error_message("session expired"):
        let (now) = get_block_timestamp()
        assert_nn(session_expires - now)
    end

    # check if the session is approved
    let (session_hash) = compute_session_hash(session_key, session_expires, root, tx_info.chain_id, tx_info.account_contract_address)
    with_attr error_message("unauthorised session"):
        IAccount.is_valid_signature(
            contract_address=tx_info.account_contract_address,
            hash=session_hash,
            sig_len=session_token_len,
            sig=session_token
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

    # check if the calls satisy the policies
    check_policy(call_array_len, call_array, root, proof_len, proofs)

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
    session_key_revoked.emit(session_key)
    return()
end

func check_policy{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        call_array_len: felt,
        call_array: CallArray*,
        root: felt,
        proof_len: felt,
        proof: felt*
     ):
    alloc_locals

    if call_array_len == 0:
        return()
    end

    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state) = hash_init()
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=POLICY_TYPE_HASH)
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=[call_array].to)
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=[call_array].selector)
        let (leaf) = hash_finalize(hash_state_ptr=hash_state)
        let pedersen_ptr = hash_ptr
    end
    
    let (proof_valid) = merkle_verify(leaf, root, proof_len, proof)
    with_attr error_message("Not allowed by policy"):
        assert proof_valid = 1
    end
    check_policy(call_array_len - 1, call_array + CallArray.SIZE, root, proof_len, proof + proof_len)
    return()
end

func compute_session_hash{
        pedersen_ptr: HashBuiltin*
    } (
        session_key: felt,
        session_expires: felt,
        root: felt,
        chain_id: felt,
        account: felt
    ) -> (hash: felt):
    alloc_locals
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state) = hash_init()
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item='StarkNet Message')
        let (domain_hash) = hash_domain(chain_id)
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=domain_hash)
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=account)
        let (message_hash) = hash_message(session_key, session_expires, root)
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=message_hash)
        let (hash) = hash_finalize(hash_state_ptr=hash_state)
        let pedersen_ptr = hash_ptr
    end
    return (hash=hash)
end

func hash_domain{hash_ptr : HashBuiltin*}(chain_id: felt) -> (hash : felt):
    let (hash_state) = hash_init()
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=STARKNET_DOMAIN_TYPE_HASH)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=chain_id)
    let (hash) = hash_finalize(hash_state_ptr=hash_state)
    return (hash=hash)
end

func hash_message{hash_ptr : HashBuiltin*}(session_key: felt, session_expires: felt, root: felt) -> (hash : felt):
    let (hash_state) = hash_init()
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=SESSION_TYPE_HASH)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=session_key)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=session_expires)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=root)
    let (hash) = hash_finalize(hash_state_ptr=hash_state)
    return (hash=hash)
end

func merkle_verify{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        leaf: felt,
        root: felt,
        proof_len: felt,
        proof: felt*
    ) -> (res: felt):
    let (calc_root) = calc_merkle_root(leaf, proof_len, proof)
    # check if calculated root is equal to expected
    if calc_root == root:
        return (1)
    else:
        return (0)
    end
end

# calculates the merkle root of a given proof
func calc_merkle_root{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        curr: felt,
        proof_len: felt,
        proof: felt*
    ) -> (res: felt):
    alloc_locals

    if proof_len == 0:
        return (curr)
    end

    local node
    local proof_elem = [proof]
    let (le) = is_le_felt(curr, proof_elem)
    
    if le == 1:
        let (n) = hash2{hash_ptr=pedersen_ptr}(curr, proof_elem)
        node = n
    else:
        let (n) = hash2{hash_ptr=pedersen_ptr}(proof_elem, curr)
        node = n
    end

    let (res) = calc_merkle_root(node, proof_len-1, proof+1)
    return (res)
end