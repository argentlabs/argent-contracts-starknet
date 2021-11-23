%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_nn
from starkware.starknet.common.syscalls import call_contract, get_tx_signature, get_contract_address
from starkware.cairo.common.hash_state import (
    hash_init, hash_finalize, hash_update, hash_update_single
)

####################
# INTERFACE
####################

@contract_interface
namespace IGuardian:
    func is_valid_signature(hash: felt, sig_len: felt, sig: felt*) -> ():
    end
end

####################
# CONSTANTS
####################

const VERSION = '0.1.0' # '0.1.0' = 30 2E 31 2E 30 = 0x302E312E30 = 206933405232

const CHANGE_SIGNER_SELECTOR = 1540130945889430637313403138889853410180247761946478946165786566748520529557
const CHANGE_GUARDIAN_SELECTOR = 1374386526556551464817815908276843861478960435557596145330240747921847320237
const CHANGE_L1_ADDRESS_SELECTOR = 279169963369459328778917024654659648799474594494056791695540097993562699432
const TRIGGER_ESCAPE_SELECTOR = 654787765132774538659281525944449989569480594447680779882263455595827967108
const CANCEL_ESCAPE_SELECTOR = 992575500541331354489361836180456905167517944319528538469723604173440834912
const ESCAPE_GUARDIAN_SELECTOR = 1662889347576632967292303062205906116436469425870979472602094601074614456040
const ESCAPE_SIGNER_SELECTOR = 578307412324655990419134484880427622068887477430675222732446709420063579565

const ESCAPE_SECURITY_PERIOD = 500 # set to e.g. 7 days in prod

####################
# STRUCTS
####################

struct Escape:
    member active_at: felt
    member caller: felt
end

####################
# STORAGE VARIABLES
####################

@storage_var
func _current_nonce() -> (res: felt):
end

@storage_var
func _signer() -> (res: felt):
end

@storage_var
func _guardian() -> (res: felt):
end

@storage_var
func _escape() -> (res: Escape):
end

@storage_var
func _L1_address() -> (res: felt):
end

####################
# EXTERNAL FUNCTIONS
####################

@constructor
func constructor{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        signer: felt,
        guardian: felt,
        L1_address: felt
    ):
    # check that the signer is not zero
    assert_not_zero(signer)
    # initialize the contract
    _signer.write(signer)
    _guardian.write(guardian)
    _L1_address.write(L1_address)
    return ()
end

@external
func execute{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        to: felt,
        selector: felt,
        calldata_len: felt,
        calldata: felt*,
        nonce: felt
    ) -> (response : felt):
    alloc_locals

    # get the signatures
    let (sig_len : felt, sig : felt*) = get_tx_signature()

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # validate signatures
    let (message_hash) = get_message_hash(to, selector, calldata_len, calldata, nonce)
    validate_signer_signature(message_hash, sig, sig_len)
    validate_guardian_signature(message_hash, sig + 2, sig_len - 2)

    # execute call
    let response = call_contract(
        contract_address=to,
        function_selector=selector,
        calldata_size=calldata_len,
        calldata=calldata
    )

    return (response=response.retdata_size)
end

@external
func change_signer{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        new_signer: felt,
        nonce: felt
    ):
    alloc_locals

    # get the signatures
    let (sig_len : felt, sig : felt*) = get_tx_signature()

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # validate signatures
    let (self) = get_contract_address()
    let calldata: felt* = alloc()
    assert calldata[0] = new_signer
    let (message_hash) = get_message_hash(self, CHANGE_SIGNER_SELECTOR, 1, calldata, nonce)
    validate_signer_signature(message_hash, sig, sig_len)
    validate_guardian_signature(message_hash, sig + 2, sig_len - 2)

    # change signer
    assert_not_zero(new_signer)
    _signer.write(new_signer)
    return()
end

@external
func change_guardian{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        new_guardian: felt,
        nonce: felt
    ):
    alloc_locals

    # get the signatures
    let (sig_len : felt, sig : felt*) = get_tx_signature()

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # validate signatures
    let (self) = get_contract_address()
    let calldata: felt* = alloc()
    assert calldata[0] = new_guardian
    let (message_hash) = get_message_hash(self, CHANGE_GUARDIAN_SELECTOR, 1, calldata, nonce)
    validate_signer_signature(message_hash, sig, sig_len)
    validate_guardian_signature(message_hash, sig + 2, sig_len - 2)

    # change guardian
    assert_not_zero(new_guardian)
    _guardian.write(new_guardian)
    return()
end

@external
func change_L1_address{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        new_L1_address: felt,
        nonce: felt
    ):
    alloc_locals

    # get the signatures
    let (sig_len : felt, sig : felt*) = get_tx_signature()

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # validate signatures
    let (self) = get_contract_address()
    let calldata: felt* = alloc()
    assert calldata[0] = new_L1_address
    let (message_hash) = get_message_hash(self, CHANGE_L1_ADDRESS_SELECTOR, 1, calldata, nonce)
    validate_signer_signature(message_hash, sig, sig_len)
    validate_guardian_signature(message_hash, sig + 2, sig_len - 2)

    # change guardian
    _L1_address.write(new_L1_address)
    return()
end

@external
func trigger_escape{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        escapor: felt,
        nonce: felt
    ):
    alloc_locals

    # get the signatures
    let (sig_len : felt, sig : felt*) = get_tx_signature()

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # no escape when the guardian is not set
    let (guardian) = _guardian.read()
    assert_not_zero(guardian)

    # check if there is already an escape
    let (current_escape) = _escape.read()
    let (signer) = _signer.read()
    if current_escape.active_at != 0:
        assert current_escape.caller = guardian
        assert escapor = signer
    end

    # validate signature
    let (self) = get_contract_address()
    let calldata: felt* = alloc()
    assert calldata[0] = escapor
    let (message_hash) = get_message_hash(self, TRIGGER_ESCAPE_SELECTOR, 1, calldata, nonce)
    if escapor == signer:
        validate_signer_signature(message_hash, sig, sig_len)
    else:
        assert escapor = guardian
        add_escape_flag(sig, sig_len)
        validate_guardian_signature(message_hash, sig, sig_len+1)
    end

    # rebinding ptrs
    local ecdsa_ptr: SignatureBuiltin* = ecdsa_ptr  

    # store new escape
    let (block_timestamp) = _block_timestamp.read()
    local new_escape: Escape = Escape(block_timestamp + ESCAPE_SECURITY_PERIOD, escapor)
    _escape.write(new_escape)
    return()
end

@external
func cancel_escape{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        nonce: felt
    ):
    alloc_locals

    # get the signatures
    let (sig_len : felt, sig : felt*) = get_tx_signature()

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # validate there is an active escape
    let (current_escape) = _escape.read()
    assert_not_zero(current_escape.active_at)

    # validate signatures
    let (self) = get_contract_address()
    let calldata: felt* = alloc()
    let (message_hash) = get_message_hash(self, CANCEL_ESCAPE_SELECTOR, 0, calldata, nonce)
    validate_signer_signature(message_hash, sig, sig_len)
    validate_guardian_signature(message_hash, sig + 2, sig_len - 2)

    # clear escape
    local new_escape: Escape = Escape(0, 0)
    _escape.write(new_escape)
    return()
end

@external
func escape_guardian{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        new_guardian: felt,
        nonce: felt
    ):
    alloc_locals

    # get the signatures
    let (sig_len : felt, sig : felt*) = get_tx_signature()

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # validate there is an active escape
    let (block_timestamp) = _block_timestamp.read()
    let (current_escape) = _escape.read()
    assert_le(current_escape.active_at, block_timestamp)

    # validate signer signatures
    let (self) = get_contract_address()
    let calldata: felt* = alloc()
    assert calldata[0] = new_guardian
    let (message_hash) = get_message_hash(self, ESCAPE_GUARDIAN_SELECTOR, 1, calldata, nonce)
    validate_signer_signature(message_hash, sig, sig_len)

    # clear escape
    local new_escape: Escape = Escape(0, 0)
    _escape.write(new_escape)

    # change guardian
    assert_not_zero(new_guardian)
    _guardian.write(new_guardian)

    return()
end

@external
func escape_signer{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        new_signer: felt,
        nonce: felt
    ):
    alloc_locals

    # get the signatures
    let (sig_len : felt, sig : felt*) = get_tx_signature()

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # validate there is an active escape
    let (block_timestamp) = _block_timestamp.read()
    let (current_escape) = _escape.read()
    assert_le(current_escape.active_at, block_timestamp)

    # validate signer signatures
    let (self) = get_contract_address()
    let calldata: felt* = alloc()
    assert calldata[0] = new_signer
    let (message_hash) = get_message_hash(self, ESCAPE_SIGNER_SELECTOR, 1, calldata, nonce)
    add_escape_flag(sig, sig_len)
    validate_guardian_signature(message_hash, sig, sig_len+1)

    # clear escape
    local new_escape: Escape = Escape(0, 0)
    _escape.write(new_escape)

    # change signer
    assert_not_zero(new_signer)
    _signer.write(new_signer)

    return()
end

####################
# VIEW FUNCTIONS
####################

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
    validate_signer_signature(hash, sig, sig_len)
    validate_guardian_signature(hash, sig + 2, sig_len - 2)
    return ()
end

@view
func get_nonce{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr}() -> (nonce: felt):
    let (res) = _current_nonce.read()
    return (nonce=res)
end

@view
func get_signer{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr}() -> (signer: felt):
    let (res) = _signer.read()
    return (signer=res)
end

@view
func get_guardian{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr}() -> (guardian: felt):
    let (res) = _guardian.read()
    return (guardian=res)
end

@view
func get_escape{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr}() -> (active_at: felt, caller: felt):
    let (res) = _escape.read()
    return (active_at=res.active_at, caller=res.caller)
end

@view
func get_L1_address{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr}() -> (L1_address: felt):
    let (res) = _L1_address.read()
    return (L1_address=res)
end

@view
func get_version() -> (version: felt):
    return (version=VERSION)
end

####################
# INTERNAL FUNCTIONS
####################

func validate_and_bump_nonce{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        message_nonce: felt
    ) -> ():
    let (current_nonce) = _current_nonce.read()
    assert current_nonce = message_nonce
    _current_nonce.write(current_nonce + 1)
    return()
end

func validate_signer_signature{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        message: felt, 
        signatures: felt*,
        signatures_len: felt
    ) -> ():
    assert_nn(signatures_len - 2)
    let (signer) = _signer.read()
    verify_ecdsa_signature(
        message=message,
        public_key=signer,
        signature_r=signatures[0],
        signature_s=signatures[1])
    return()
end

func validate_guardian_signature{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        message: felt,
        signatures: felt*,
        signatures_len: felt
    ) -> ():
    alloc_locals
    let (guardian) = _guardian.read()
    local pedersen_ptr: HashBuiltin* = pedersen_ptr
    if guardian == 0:
        return()
    else:
        assert_nn(signatures_len - 2)
        IGuardian.is_valid_signature(contract_address=guardian, hash=message, sig_len=signatures_len, sig=signatures)
        return()
    end
end

func add_escape_flag{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        sig: felt*,
        sig_len: felt
    ) -> ():
    assert [sig + sig_len] = 'escape'
    return()
end

func get_message_hash{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        to: felt,
        selector: felt,
        calldata_len: felt,
        calldata: felt*,
        nonce: felt
    ) -> (res: felt):
    alloc_locals
    let (account) = get_contract_address()
    let (calldata_hash) = hash_calldata(calldata, calldata_len)
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, account)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, to)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, selector)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, calldata_hash)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, nonce)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (res=res)
    end
    
end

func hash_calldata{
        pedersen_ptr: HashBuiltin*
    }(
        calldata: felt*,
        calldata_size: felt
    ) -> (res: felt):
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update(
            hash_state_ptr,
            calldata,
            calldata_size
        )
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (res=res)
    end
end

####################
# TMP HACK
####################

@storage_var
func _block_timestamp() -> (res: felt):
end

@view
func get_block_timestamp{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr}() -> (block_timestamp: felt):
    let (res) = _block_timestamp.read()
    return (block_timestamp=res)
end

@external
func set_block_timestamp{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr}(new_block_timestamp: felt):
    _block_timestamp.write(new_block_timestamp)
    return ()
end