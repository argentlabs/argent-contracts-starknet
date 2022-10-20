%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.hash_state import (
    HashState,
    hash_finalize,
    hash_init,
    hash_update,
    hash_update_single,
)
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_nn
from starkware.starknet.common.syscalls import get_tx_info, get_block_timestamp

// H('StarkNetDomain(chainId:felt)')
const STARKNET_DOMAIN_TYPE_HASH = 0x13cda234a04d66db62c06b8e3ad5f91bd0c67286c2c7519a826cf49da6ba478;
// H('Session(key:felt,expires:felt,root:merkletree)')
const SESSION_TYPE_HASH = 0x1aa0e1c56b45cf06a54534fa1707c54e520b842feb21d03b7deddb6f1e340c;
// H(Policy(contractAddress:felt,selector:selector))
const POLICY_TYPE_HASH = 0x2f0026e78543f036f33e26a8f5891b88c58dc1e20cbbfaf0bb53274da6fa568;

@contract_interface
namespace IAccount {
    func isValidSignature(hash: felt, sig_len: felt, sig: felt*) {
    }
}

struct CallArray {
    to: felt,
    selector: felt,
    data_offset: felt,
    data_len: felt,
}

@event
func session_key_revoked(session_key: felt) {
}

@storage_var
func SessionKey_revoked_keys(key: felt) -> (res: felt) {
}

@external
func initialize(data_len: felt, data: felt*) {
    return ();
}

@external
func validate{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(
    call_array_len: felt,
    call_array: CallArray*,
    calldata_len: felt,
    calldata: felt*,
) {
    alloc_locals;

    // get the tx info
    let (tx_info) = get_tx_info();

    // parse the plugin data
    with_attr error_message("invalid plugin data") {
        assert_nn(tx_info.signature_len - 4);
        let session_key = [tx_info.signature];
        let session_expires = [tx_info.signature + 1];
        let root = [tx_info.signature + 2];
        let proof_len = [tx_info.signature + 3];
        let proofs_len = proof_len * call_array_len;
        let proofs : felt* = tx_info.signature + 4;
        let session_token_len = tx_info.signature_len - 4 - proofs_len;
        assert_nn(session_token_len);
        let session_token : felt* = tx_info.signature + 4 + proofs_len;
        let session_signature : felt* = session_token + session_token_len;
    }

    // check if the session has expired
    with_attr error_message("session expired") {
        let (now) = get_block_timestamp();
        assert_nn(session_expires - now);
    }

    // check if the session is approved
    with_attr error_message("unauthorised session") {
        let (session_hash) = compute_session_hash(
            session_key, session_expires, root, tx_info.chain_id, tx_info.account_contract_address
        );
        IAccount.isValidSignature(
            contract_address=tx_info.account_contract_address,
            hash=session_hash,
            sig_len=session_token_len,
            sig=session_token,
        );
    }

    // check if the session key is revoked
    with_attr error_message("session key revoked") {
        let (is_revoked) = SessionKey_revoked_keys.read(session_key);
        assert is_revoked = 0;
    }

    // check if the tx is signed by the session key
    with_attr error_message("session key signature invalid") {
        verify_ecdsa_signature(
            message=tx_info.transaction_hash,
            public_key=session_key,
            signature_r=session_signature[0],
            signature_s=session_signature[1],
        );
    }

    // check if the calls satisy the policies
    with_attr error_message("not allowed by policy") {
        check_policy(call_array_len, call_array, root, proof_len, proofs);
    }

    return ();
}

@external
func revokeSession{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    session_key: felt
) {
    SessionKey_revoked_keys.write(session_key, 1);
    session_key_revoked.emit(session_key);
    return ();
}

func check_policy{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(call_array_len: felt, call_array: CallArray*, root: felt, proof_len: felt, proof: felt*) {
    alloc_locals;

    if (call_array_len == 0) {
        return ();
    }

    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state) = hash_init();
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=POLICY_TYPE_HASH);
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=[call_array].to);
        let (hash_state) = hash_update_single(
            hash_state_ptr=hash_state, item=[call_array].selector
        );
        let (leaf) = hash_finalize(hash_state_ptr=hash_state);
        let pedersen_ptr = hash_ptr;
    }

    let (proof_valid) = merkle_verify(leaf, root, proof_len, proof);
    assert proof_valid = 1;

    check_policy(
        call_array_len - 1, call_array + CallArray.SIZE, root, proof_len, proof + proof_len
    );
    return ();
}

func compute_session_hash{pedersen_ptr: HashBuiltin*}(
    session_key: felt, session_expires: felt, root: felt, chain_id: felt, account: felt
) -> (hash: felt) {
    alloc_locals;
    let hash_ptr = pedersen_ptr;
    with hash_ptr {
        let (hash_state) = hash_init();
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item='StarkNet Message');
        let (domain_hash) = hash_domain(chain_id);
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=domain_hash);
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=account);
        let (message_hash) = hash_message(session_key, session_expires, root);
        let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=message_hash);
        let (hash) = hash_finalize(hash_state_ptr=hash_state);
        let pedersen_ptr = hash_ptr;
    }
    return (hash=hash);
}

func hash_domain{hash_ptr: HashBuiltin*}(chain_id: felt) -> (hash: felt) {
    let (hash_state) = hash_init();
    let (hash_state) = hash_update_single(
        hash_state_ptr=hash_state, item=STARKNET_DOMAIN_TYPE_HASH
    );
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=chain_id);
    let (hash) = hash_finalize(hash_state_ptr=hash_state);
    return (hash=hash);
}

func hash_message{hash_ptr: HashBuiltin*}(session_key: felt, session_expires: felt, root: felt) -> (
    hash: felt
) {
    let (hash_state) = hash_init();
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=SESSION_TYPE_HASH);
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=session_key);
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=session_expires);
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=root);
    let (hash) = hash_finalize(hash_state_ptr=hash_state);
    return (hash=hash);
}

func merkle_verify{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    leaf: felt, root: felt, proof_len: felt, proof: felt*
) -> (res: felt) {
    let (calc_root) = calc_merkle_root(leaf, proof_len, proof);
    // check if calculated root is equal to expected
    if (calc_root == root) {
        return (1,);
    } else {
        return (0,);
    }
}

// calculates the merkle root of a given proof
func calc_merkle_root{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    curr: felt, proof_len: felt, proof: felt*
) -> (res: felt) {
    alloc_locals;

    if (proof_len == 0) {
        return (curr,);
    }

    local node;
    local proof_elem = [proof];
    let le = is_le_felt(curr, proof_elem);

    if (le == 1) {
        let (n) = hash2{hash_ptr=pedersen_ptr}(curr, proof_elem);
        node = n;
    } else {
        let (n) = hash2{hash_ptr=pedersen_ptr}(proof_elem, curr);
        node = n;
    }

    let (res) = calc_merkle_root(node, proof_len - 1, proof + 1);
    return (res,);
}
