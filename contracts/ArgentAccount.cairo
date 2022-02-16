%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_nn
from starkware.starknet.common.syscalls import (
    call_contract, get_tx_info, get_contract_address, get_caller_address, get_block_timestamp
)
from starkware.cairo.common.hash_state import (
    hash_init, hash_finalize, hash_update, hash_update_single
)

from contracts.Upgradable import _set_implementation

####################
# CONSTANTS
####################

const VERSION = '0.2.0' # '0.2.0' = 30 2E 32 2E 30 = 0x302E322E30 = 206933470768

const CHANGE_SIGNER_SELECTOR = 1540130945889430637313403138889853410180247761946478946165786566748520529557
const CHANGE_GUARDIAN_SELECTOR = 1374386526556551464817815908276843861478960435557596145330240747921847320237
const TRIGGER_ESCAPE_GUARDIAN_SELECTOR = 73865429733192804476769961144708816295126306469589518371407068321865763651
const TRIGGER_ESCAPE_SIGNER_SELECTOR = 651891265762986954898774236860523560457159526623523844149280938288756256223
const ESCAPE_GUARDIAN_SELECTOR = 1662889347576632967292303062205906116436469425870979472602094601074614456040
const ESCAPE_SIGNER_SELECTOR = 578307412324655990419134484880427622068887477430675222732446709420063579565
const CANCEL_ESCAPE_SELECTOR = 992575500541331354489361836180456905167517944319528538469723604173440834912

const ESCAPE_SECURITY_PERIOD = 7*24*60*60 # set to e.g. 7 days in prod

const ESCAPE_TYPE_GUARDIAN = 0
const ESCAPE_TYPE_SIGNER = 1

const PREFIX_TRANSACTION = 'StarkNet Transaction'

####################
# STRUCTS
####################

struct Call_Input:
    member to: felt
    member selector: felt
    member data_offset: felt
    member data_len: felt
end

struct Call:
    member to: felt
    member selector: felt
    member calldata_len: felt
    member calldata: felt*
end

struct Escape:
    member active_at: felt
    member type: felt
end

####################
# EVENTS
####################

@event
func signer_changed(new_signer: felt):
end

@event
func guardian_changed(new_guardian: felt):
end

@event
func guardian_backup_changed(new_guardian: felt):
end

@event
func escape_guardian_triggered(active_at: felt):
end

@event
func escape_signer_triggered(active_at: felt):
end

@event
func escape_canceled():
end

@event
func guardian_escaped(new_guardian: felt):
end

@event
func signer_escaped(new_signer: felt):
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
func _guardian_backup() -> (res: felt):
end

@storage_var
func _escape() -> (res: Escape):
end

####################
# EXTERNAL FUNCTIONS
####################

@external
func initialize{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        signer: felt,
        guardian: felt
    ):
    # check that we are not already initialized
    let (current_signer) = _signer.read()
    assert current_signer = 0
    # check that the target signer is not zero
    assert_not_zero(signer)
    # initialize the contract
    _signer.write(signer)
    _guardian.write(guardian)
    return ()
end

@external
func __execute__{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr
    } (
        call_input_len: felt,
        call_input: Call_Input*,
        calldata_len: felt,
        calldata: felt*,
        nonce
    ) -> (
        response_len: felt,
        response: felt*
    ):
    alloc_locals

    ############### TMP #############################
    # parse inputs to an array of 'Call' struct
    let (calls : Call*) = alloc()
    parse_input(call_input_len, call_input, calldata, calls)
    let calls_len = call_input_len
    #################################################

    # validate and bump nonce
    validate_and_bump_nonce(nonce)

    # get the tx info
    let (tx_info) = get_tx_info()

    # compute message hash
    let (message_hash) = get_execute_hash(tx_info.account_contract_address, calls_len, calls, nonce, tx_info.max_fee, tx_info.version)

    if calls_len == 1:
        if calls[0].to == tx_info.account_contract_address:
            tempvar signer_condition = (calls[0].selector - ESCAPE_GUARDIAN_SELECTOR) * (calls[0].selector - TRIGGER_ESCAPE_GUARDIAN_SELECTOR)
            tempvar guardian_condition = (calls[0].selector - ESCAPE_SIGNER_SELECTOR) * (calls[0].selector - TRIGGER_ESCAPE_SIGNER_SELECTOR)
            if signer_condition == 0:
                # validate signer signature
                validate_signer_signature(message_hash, tx_info.signature, tx_info.signature_len)
                jmp do_execute
            end
            if guardian_condition == 0:
                # validate guardian signature
                validate_guardian_signature(message_hash, tx_info.signature, tx_info.signature_len)
                jmp do_execute
            end
        end
    else:
        # make sure no call is to the account
        assert_no_self_call(tx_info.account_contract_address, calls_len, calls)
    end
    # validate signer and guardian signatures
    validate_signer_signature(message_hash, tx_info.signature, tx_info.signature_len)
    validate_guardian_signature(message_hash, tx_info.signature + 2, tx_info.signature_len - 2)

    # execute calls
    do_execute:
    local ecdsa_ptr: SignatureBuiltin* = ecdsa_ptr
    local syscall_ptr: felt* = syscall_ptr
    local range_check_ptr = range_check_ptr
    local pedersen_ptr: HashBuiltin* = pedersen_ptr
    let (response : felt*) = alloc()
    let (response_len) = execute_list(calls_len, calls, response)
    return (response_len=response_len, response=response)
end

@external
func upgrade{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        implementation: felt
    ):
    # only called via execute
    assert_only_self()
    # change implementation
    _set_implementation(implementation)
    return()
end

@external
func change_signer{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        new_signer: felt
    ):
    # only called via execute
    assert_only_self()

    # change signer
    assert_not_zero(new_signer)
    _signer.write(new_signer)
    signer_changed.emit(new_signer=new_signer)
    return()
end

@external
func change_guardian{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        new_guardian: felt
    ):
    # only called via execute
    assert_only_self()
    
    # assert !(guardian_backup != 0 && new_guardian == 0)
    if new_guardian == 0:
        let (guardian_backup) = _guardian_backup.read()
        with_attr error_message("new guardian cannot be null"):
            assert guardian_backup = 0
        end
        tempvar syscall_ptr: felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr: felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr
    end

    # change guardian
    _guardian.write(new_guardian)
    guardian_changed.emit(new_guardian=new_guardian)
    return()
end

@external
func change_guardian_backup{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        new_guardian: felt
    ):
    # only called via execute
    assert_only_self()

    # no backup when there is no guardian set
    assert_guardian_set()

    # change guardian
    _guardian_backup.write(new_guardian)
    guardian_backup_changed.emit(new_guardian=new_guardian)
    return()
end

@external
func trigger_escape_guardian{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } ():
    # only called via execute
    assert_only_self()

    # no escape when the guardian is not set
    assert_guardian_set()

    # store new escape
    let (block_timestamp) = get_block_timestamp()
    let new_escape: Escape = Escape(block_timestamp + ESCAPE_SECURITY_PERIOD, ESCAPE_TYPE_GUARDIAN)
    _escape.write(new_escape)
    escape_guardian_triggered.emit(active_at=block_timestamp + ESCAPE_SECURITY_PERIOD)
    return()
end

@external
func trigger_escape_signer{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } ():
    # only called via execute
    assert_only_self()
    
    # no escape when there is no guardian set
    assert_guardian_set()

    # no escape if there is an guardian escape triggered by the signer in progress
    let (current_escape) = _escape.read()
    with_attr error_message("cannot overrride signer escape"):
        assert current_escape.active_at * (current_escape.type - ESCAPE_TYPE_SIGNER) = 0
    end

    # store new escape
    let (block_timestamp) = get_block_timestamp()
    let new_escape: Escape = Escape(block_timestamp + ESCAPE_SECURITY_PERIOD, ESCAPE_TYPE_SIGNER)
    _escape.write(new_escape)
    escape_signer_triggered.emit(active_at=block_timestamp + ESCAPE_SECURITY_PERIOD)
    return()
end

@external
func cancel_escape{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } ():

    # only called via execute
    assert_only_self()

    # validate there is an active escape
    let (current_escape) = _escape.read()
    with_attr error_message("no escape to cancel"):
        assert_not_zero(current_escape.active_at)
    end

    # clear escape
    let new_escape: Escape = Escape(0, 0)
    _escape.write(new_escape)
    escape_canceled.emit()
    return()
end

@external
func escape_guardian{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        new_guardian: felt
    ):
    alloc_locals

    # only called via execute
    assert_only_self()
    # no escape when the guardian is not set
    assert_guardian_set()
    
    let (current_escape) = _escape.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("escape is not valid"):
        # assert there is an active escape
        assert_le(current_escape.active_at, block_timestamp)
        # assert the escape was triggered by the signer
        assert current_escape.type = ESCAPE_TYPE_GUARDIAN
    end

    # clear escape
    let new_escape: Escape = Escape(0, 0)
    _escape.write(new_escape)

    # change guardian
    assert_not_zero(new_guardian)
    _guardian.write(new_guardian)
    guardian_escaped.emit(new_guardian=new_guardian)

    return()
end

@external
func escape_signer{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        new_signer: felt
    ):
    alloc_locals

    # only called via execute
    assert_only_self()
    # no escape when the guardian is not set
    assert_guardian_set()

    let (current_escape) = _escape.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("escape is not valid"):
        # validate there is an active escape
        assert_le(current_escape.active_at, block_timestamp)
        # assert the escape was triggered by the guardian
        assert current_escape.type = ESCAPE_TYPE_SIGNER
    end

    # clear escape
    let new_escape: Escape = Escape(0, 0)
    _escape.write(new_escape)

    # change signer
    assert_not_zero(new_signer)
    _signer.write(new_signer)
    signer_escaped.emit(new_signer=new_signer)

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
        range_check_ptr
    } () -> (nonce: felt):
    let (res) = _current_nonce.read()
    return (nonce=res)
end

@view
func get_signer{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } () -> (signer: felt):
    let (res) = _signer.read()
    return (signer=res)
end

@view
func get_guardian{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } () -> (guardian: felt):
    let (res) = _guardian.read()
    return (guardian=res)
end

@view
func get_guardian_backup{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } () -> (guardian_backup: felt):
    let (res) = _guardian_backup.read()
    return (guardian_backup=res)
end

@view
func get_escape{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } () -> (active_at: felt, type: felt):
    let (res) = _escape.read()
    return (active_at=res.active_at, type=res.type)
end

@view
func get_version() -> (version: felt):
    return (version=VERSION)
end

####################
# INTERNAL FUNCTIONS
####################

func assert_only_self{
        syscall_ptr: felt*
    } () -> ():
    let (self) = get_contract_address()
    let (caller_address) = get_caller_address()
    with_attr error_message("must be called via execute"):
        assert self = caller_address
    end
    return()
end

func assert_guardian_set{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } ():
    let (guardian) = _guardian.read()
    with_attr error_message("guardian must be set"):
        assert_not_zero(guardian)
    end
    return()
end

func assert_no_self_call(
        self: felt,
        calls_len: felt,
        calls: Call*
    ):
    if calls_len == 0:
        return ()
    end
    assert_not_zero(calls[0].to - self)
    assert_no_self_call(self, calls_len - 1, calls + Call.SIZE)
    return()
end

func validate_and_bump_nonce{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        message_nonce: felt
    ) -> ():
    let (current_nonce) = _current_nonce.read()
    with_attr error_message("nonce invalid"):
        assert current_nonce = message_nonce
    end
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
    with_attr error_message("signer signature invalid"):
        assert_nn(signatures_len - 2)
        let (signer) = _signer.read()
        verify_ecdsa_signature(
            message=message,
            public_key=signer,
            signature_r=signatures[0],
            signature_s=signatures[1])
    end
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
    if guardian == 0:
        return()
    else:
        with_attr error_message("guardian signature invalid"):
            if signatures_len == 2:
                # must be signed by guardian
                verify_ecdsa_signature(
                    message=message,
                    public_key=guardian,
                    signature_r=signatures[0],
                    signature_s=signatures[1])
                tempvar syscall_ptr: felt* = syscall_ptr
                tempvar range_check_ptr = range_check_ptr
                tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr
            else:
                # must be signed by guardian_backup
                assert signatures_len = 4
                assert (signatures[0] + signatures[1]) = 0
                let (guardian_backup) = _guardian_backup.read()
                verify_ecdsa_signature(
                    message=message,
                    public_key=guardian_backup,
                    signature_r=signatures[2],
                    signature_s=signatures[3])
                tempvar syscall_ptr: felt* = syscall_ptr
                tempvar range_check_ptr = range_check_ptr
                tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr
            end
        end
        return()
    end
end

# @notice Executes a list of contract calls recursively.
# @param calls_len The number of calls to execute
# @param calls A pointer to the first call to execute
# @param response The array of felt to pupulate with the returned data
# @return response_len The size of the returned data
func execute_list{
        syscall_ptr: felt*
    } (
        calls_len: felt,
        calls: Call*,
        reponse: felt*
    ) -> (
        response_len: felt,
    ):
    alloc_locals

    # if no more calls
    if calls_len == 0:
       return (0)
    end
    
    # do the current call
    let this_call: Call = [calls]
    let res = call_contract(
        contract_address=this_call.to,
        function_selector=this_call.selector,
        calldata_size=this_call.calldata_len,
        calldata=this_call.calldata
    )
    # copy the result in response
    memcpy(reponse, res.retdata, res.retdata_size)
    # do the next calls recursively
    let (response_len) = execute_list(calls_len - 1, calls + Call.SIZE, reponse + res.retdata_size)
    return (response_len + res.retdata_size)
end

# @notice Computes the hash of a multicall to the `execute` method.
# @param calls_len The legnth of the array of `Call`
# @param calls A pointer to the array of `Call`
# @param nonce The nonce for the multicall transaction
# @param max_fee The max fee the user is willing to pay for the multicall
# @param version The version of transaction in the Cairo OS. Always set to 0.
# @return res The hash of the multicall
func get_execute_hash{
        syscall_ptr: felt*, 
        pedersen_ptr: HashBuiltin*
    } (
        account: felt,
        calls_len: felt,
        calls: Call*,
        nonce: felt,
        max_fee: felt,
        version: felt
    ) -> (res: felt):
    alloc_locals
    let (calls_hash) = hash_call_array(calls_len, calls)
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, PREFIX_TRANSACTION)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, account)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, calls_hash)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, nonce)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, max_fee)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, version)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (res=res)
    end
end

# @notice Computes the hash of an array of `Call`
# @param calls_len The legnth of the array of `Call`
# @param calls A pointer to the array of `Call`
# @return res The hash of the array of `Call`
func hash_call_array{
        pedersen_ptr: HashBuiltin*
    }(
        calls_len: felt,
        calls: Call*
    ) -> (
        res: felt
    ):
    alloc_locals

    let (hash_array : felt*) = alloc()
    hash_call_loop(calls_len, calls, hash_array)

    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update(hash_state_ptr, hash_array, calls_len)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (res=res)
    end
end

# @notice Turns an array of `Call` into an array of `hash(Call)`
# @param calls_len The legnth of the array of `Call`
# @param calls A pointer to the array of `Call`
# @param hash_array A pointer to the array of `hash(Call)`
func hash_call_loop{
        pedersen_ptr: HashBuiltin*
    } (
        calls_len: felt,
        calls: Call*,
        hash_array: felt*
    ):
    if calls_len == 0:
        return ()
    end
    let this_call = [calls]
    let (calldata_hash) = hash_calldata(this_call.calldata_len, this_call.calldata)
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, this_call.to)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, this_call.selector)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, calldata_hash)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        assert [hash_array] = res
    end
    hash_call_loop(calls_len - 1, calls + Call.SIZE, hash_array + 1)
    return()
end

# @notice Computes the hash of calldata as an array of felt
# @param calldata_len The length of the calldata array
# @param calldata A pointer to the calldata array
# @return the hash of the calldata
func hash_calldata{
        pedersen_ptr: HashBuiltin*
    } (
        calldata_len: felt,
        calldata: felt*,
    ) -> (
        res: felt
    ):
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update(hash_state_ptr, calldata, calldata_len)
        let (res) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (res=res)
    end
end

func parse_input{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (
        input_len: felt,
        input: Call_Input*,
        calldata: felt*,
        calls: Call*
    ):
    alloc_locals

    # if no more inputs
    if input_len == 0:
       return ()
    end
    
    # parse the first input
    assert [calls] = Call(
            to=[input].to,
            selector=[input].selector,
            calldata_len=[input].data_len,
            calldata=calldata + [input].data_offset)
    
    # parse the other inputs recursively
    parse_input(input_len - 1, input + Call_Input.SIZE, calldata, calls + Call.SIZE)
    return ()
end
