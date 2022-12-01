import pytest

from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from utils.Signer import Signer
from utils.utilities import cached_contract, compile, assert_revert, str_to_felt, assert_event_emitted, update_starknet_block, reset_starknet_block, DEFAULT_TIMESTAMP
from utils.TransactionSender import TransactionSender

signer = Signer(1)
guardian = Signer(2)
guardian_backup = Signer(3)

new_signer = Signer(4)
new_guardian = Signer(5)
new_guardian_backup = Signer(6)

wrong_signer = Signer(7)
wrong_guardian = Signer(8)

ESCAPE_SECURITY_PERIOD = 24*7*60*60

VERSION = str_to_felt('0.2.3')
NAME = str_to_felt('ArgentAccount')

IACCOUNT_ID = 0x3943f10f

ESCAPE_TYPE_GUARDIAN = 1
ESCAPE_TYPE_SIGNER = 2


@pytest.fixture(scope='module')
async def contract_init(account_cls: ContractClass, test_dapp_cls: ContractClass):
    starknet = await Starknet.empty()

    account = await starknet.deploy(
        contract_class=account_cls,
        constructor_calldata=[]
    )
    await account.initialize(signer.public_key, guardian.public_key).execute()

    account_no_guardian = await starknet.deploy(
        contract_class=account_cls,
        constructor_calldata=[]
    )
    await account_no_guardian.initialize(signer.public_key, 0).execute()

    dapp = await starknet.deploy(
        contract_class=test_dapp_cls,
        constructor_calldata=[],
    )

    return starknet.state, account, account_no_guardian, dapp


@pytest.fixture
async def contract_factory(account_cls: ContractClass, test_dapp_cls: ContractClass, contract_init):
    state, account, account_no_guardian, dapp = contract_init
    _state = state.copy()

    account = cached_contract(_state, account_cls, account)
    account_no_guardian = cached_contract(_state, account_cls, account_no_guardian)
    dapp = cached_contract(_state, test_dapp_cls, dapp)

    return account, account_no_guardian, dapp


async def test_initializer(contract_factory):
    account, _, _ = contract_factory
    # should be configured correctly
    assert (await account.getSigner().call()).result.signer == (signer.public_key)
    assert (await account.getGuardian().call()).result.guardian == (guardian.public_key)
    assert (await account.getVersion().call()).result.version == VERSION
    assert (await account.getName().call()).result.name == NAME
    assert (await account.supportsInterface(IACCOUNT_ID).call()).result.success == 1
    # should throw when calling initialize twice
    await assert_revert(
         account.initialize(signer.public_key, guardian.public_key).execute(),
         "argent: already initialized"
     )


async def test_declare(contract_factory):
    account, _, _ = contract_factory
    sender = TransactionSender(account)

    test_cls = compile("contracts/test/StructHash.cairo")

    # should revert with only one signature
    await assert_revert(
        sender.declare_class(test_cls, [signer]),
        "argent: signature format invalid"
    )

    # should revert with wrong signer
    await assert_revert(
        sender.declare_class(test_cls, [wrong_signer, guardian]),
        "argent: signer signature invalid"
    )

    # should revert with wrong guardian
    await assert_revert(
        sender.declare_class(test_cls, [signer, wrong_guardian]),
        "argent: guardian signature invalid"
    )

    tx_exec_info = await sender.declare_class(test_cls, [signer, guardian])



async def test_call_dapp_with_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    calls = [(dapp.contract_address, 'set_number', [47])]

    # should revert with the wrong nonce
    await assert_revert(
        sender.send_transaction(calls, [signer, guardian], nonce=3),
        expected_code=StarknetErrorCode.INVALID_TRANSACTION_NONCE
    )

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction(calls, [wrong_signer, guardian]),
        "argent: signer signature invalid"
    )

    # should revert with the wrong guardian
    await assert_revert(
        sender.send_transaction(calls, [signer, wrong_guardian]),
        "argent: guardian signature invalid"
    )

    # should revert when the signature format is not valid
    await assert_revert(
        sender.send_transaction(calls, [signer, guardian, wrong_guardian]),
        "argent: signature format invalid"
    )

    # should fail with only 1 signer
    await assert_revert(
        sender.send_transaction(calls, [signer]),
        "argent: signature format invalid"
    )

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    
    tx_exec_info = await sender.send_transaction(calls, [signer, guardian])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='transaction_executed'
    )

    assert (await dapp.get_number(account.contract_address).call()).result.number == 47


async def test_call_dapp_guardian_backup(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # add guardian backup
    await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [guardian_backup.public_key])], [signer, guardian])

    calls = [(dapp.contract_address, 'set_number', [47])]

    # should revert with the wrong guardian
    await assert_revert(
        sender.send_transaction(calls, [signer, 0, wrong_guardian]),
        "argent: guardian backup signature invalid"
    )

    # should revert when the signature format is not valid
    await assert_revert(
        sender.send_transaction(calls, [signer, guardian, guardian_backup]),
        "argent: signature format invalid"
    )

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    
    tx_exec_info = await sender.send_transaction(calls, [signer, 0, guardian_backup])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='transaction_executed'
    )

    assert (await dapp.get_number(account.contract_address).call()).result.number == 47


async def test_call_dapp_no_guardian(contract_factory):
    _, account_no_guardian, dapp = contract_factory
    sender = TransactionSender(account_no_guardian)

    # should call the dapp
    assert (await dapp.get_number(account_no_guardian.contract_address).call()).result.number == 0
    await sender.send_transaction([(dapp.contract_address, 'set_number', [47])], [signer])
    assert (await dapp.get_number(account_no_guardian.contract_address).call()).result.number == 47

    # should change the signer
    assert (await account_no_guardian.getSigner().call()).result.signer == (signer.public_key)
    await sender.send_transaction([(account_no_guardian.contract_address, 'changeSigner', [new_signer.public_key])], [signer])
    assert (await account_no_guardian.getSigner().call()).result.signer == (new_signer.public_key)

    # should revert calls that require the guardian to be set
    await assert_revert(
        sender.send_transaction([(account_no_guardian.contract_address, 'triggerEscapeGuardian', [])], [new_signer]),
        "argent: guardian required"
    )

    # should add a guardian
    assert (await account_no_guardian.getGuardian().call()).result.guardian == (0)
    await sender.send_transaction([(account_no_guardian.contract_address, 'changeGuardian', [new_guardian.public_key])], [new_signer])
    assert (await account_no_guardian.getGuardian().call()).result.guardian == (new_guardian.public_key)


async def test_multicall(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # should revert when one of the call is to the account
    await assert_revert(
        sender.send_transaction([(dapp.contract_address, 'set_number', [47]), (account.contract_address, 'triggerEscapeGuardian', [])], [signer, guardian])
    )
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'triggerEscapeGuardian', []), (dapp.contract_address, 'set_number', [47])], [signer, guardian])
    )

    # should indicate which called failed
    await assert_revert(
        sender.send_transaction([(dapp.contract_address, 'set_number', [47]), (dapp.contract_address, 'throw_error', [1])], [signer, guardian]),
        "multicall 1 failed"
    )
    await assert_revert(
        sender.send_transaction([(dapp.contract_address, 'throw_error', [1]), (dapp.contract_address, 'set_number', [47])], [signer, guardian]),
        "multicall 0 failed"
    )

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction([(dapp.contract_address, 'set_number', [47]), (dapp.contract_address, 'increase_number', [10])], [signer, guardian])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 57


async def test_change_signer(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    assert (await account.getSigner().call()).result.signer == signer.public_key

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'changeSigner', [new_signer.public_key])], [wrong_signer, guardian]),
        "argent: signer signature invalid"
    )

    # should revert with the wrong guardian signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'changeSigner', [new_signer.public_key])], [signer, wrong_guardian]),
        "argent: guardian signature invalid"
    )

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'changeSigner', [new_signer.public_key])], [signer, guardian])
    
    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='signer_changed',
        data=[new_signer.public_key]
    )

    assert (await account.getSigner().call()).result.signer == (new_signer.public_key)


async def test_change_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    assert (await account.getGuardian().call()).result.guardian == (guardian.public_key)

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'changeGuardian', [new_guardian.public_key])], [wrong_signer, guardian]),
        "argent: signer signature invalid"
    )

    # should revert with the wrong guardian signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'changeGuardian', [new_guardian.public_key])], [signer, wrong_guardian]),
        "argent: guardian signature invalid"
    )

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'changeGuardian', [new_guardian.public_key])], [signer, guardian])
    
    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_changed',
        data=[new_guardian.public_key]
    )

    assert (await account.getGuardian().call()).result.guardian == (new_guardian.public_key)


async def test_change_guardian_backup(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [new_guardian_backup.public_key])], [wrong_signer, guardian]),
        "argent: signer signature invalid"
    )

    # should revert with the wrong guardian signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [new_guardian_backup.public_key])], [signer, wrong_guardian]),
        "argent: guardian signature invalid"
    )

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [new_guardian_backup.public_key])], [signer, guardian])
    
    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_backup_changed',
        data=[new_guardian_backup.public_key]
    )

    assert (await account.getGuardianBackup().call()).result.guardianBackup == (new_guardian_backup.public_key)


async def test_change_guardian_backup_when_no_guardian(contract_factory):
    _, account_no_guardian, dapp = contract_factory
    sender = TransactionSender(account_no_guardian)

    await assert_revert(
        sender.send_transaction([(account_no_guardian.contract_address, 'changeGuardianBackup', [new_guardian_backup.public_key])], [signer])
    )


async def test_change_guardian_when_guardian_backup(contract_factory):
    account, _, _ = contract_factory
    sender = TransactionSender(account)

    # add guardian backup
    await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [guardian_backup.public_key])], [signer, guardian])

    await assert_revert(
        sender.send_transaction([(account.contract_address, 'changeGuardian', [0])], [signer, guardian]),
        "argent: new guardian invalid"
    )


async def test_trigger_escape_guardian_by_signer(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(state=account.state)

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'triggerEscapeGuardian', [])], [signer])
    
    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_guardian_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)


async def test_trigger_escape_signer_by_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(state=account.state)

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [guardian])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_signer_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)


async def test_trigger_escape_signer_by_guardian_backup(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # set guardian backup
    await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [guardian_backup.public_key])], [signer, guardian])
    
    # reset block_timestamp
    reset_starknet_block(state=account.state)

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [0, guardian_backup])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_signer_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)


async def test_escape_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # reset block_timestamp
    reset_starknet_block(state=account.state)

    # should revert when there is no escape
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'escapeGuardian', [new_guardian.public_key])], [signer]),
        "argent: not escaping"
    )

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'triggerEscapeGuardian', [])], [signer])

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)

    # should fail to escape before the end of the period
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'escapeGuardian', [new_guardian.public_key])], [signer]),
        "argent: escape not active"
    )

    # wait security period
    update_starknet_block(state=account.state, block_timestamp=(DEFAULT_TIMESTAMP+ESCAPE_SECURITY_PERIOD))

    # should escape after the security period
    assert (await account.getGuardian().call()).result.guardian == (guardian.public_key)
    
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'escapeGuardian', [new_guardian.public_key])], [signer])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_escaped',
        data=[new_guardian.public_key]
    )

    assert (await account.getGuardian().call()).result.guardian == (new_guardian.public_key)

    # escape should be cleared
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0 and escape.type == 0)


async def test_escape_signer(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(state=account.state)

    # should revert when there is no escape
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'escapeSigner', [new_signer.public_key])], [guardian]),
        "argent: not escaping"
    )

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [guardian])
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

    # should fail to escape before the end of the period
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'escapeSigner', [new_signer.public_key])], [guardian]),
        "argent: escape not active"
    )

    # wait security period
    update_starknet_block(state=account.state, block_timestamp=(DEFAULT_TIMESTAMP+ESCAPE_SECURITY_PERIOD))

    # should escape after the security period
    assert (await account.getSigner().call()).result.signer == (signer.public_key)
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'escapeSigner', [new_signer.public_key])], [guardian])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='signer_escaped',
        data=[new_signer.public_key]
    )

    assert (await account.getSigner().call()).result.signer == (new_signer.public_key)

    # escape should be cleared
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0 and escape.type == 0)


async def test_signer_overrides_trigger_escape_signer(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(state=account.state)

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [guardian])
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

    # wait few seconds
    update_starknet_block(state=account.state, block_timestamp=(DEFAULT_TIMESTAMP+100))

    # signer overrides escape
    await sender.send_transaction([(account.contract_address, 'triggerEscapeGuardian', [])], [signer])
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + 100 + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)


async def test_guardian_overrides_trigger_escape_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(state=account.state)

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'triggerEscapeGuardian', [])], [signer])
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)

    # wait few seconds
    update_starknet_block(state=account.state, block_timestamp=(DEFAULT_TIMESTAMP+100))

    # guradian tries to override escape => should fail
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [guardian]),
        "argent: cannot override escape"
    )


async def test_cancel_escape(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(state=account.state)

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [guardian])
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

    # should fail to cancel with only the signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'cancelEscape', [])], [signer]),
        "argent: signature format invalid"
    )

    # cancel escape
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'cancelEscape', [])], [signer, guardian])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_canceled',
        data=[]
    )

    # escape should be cleared
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0 and escape.type == 0)


async def test_is_valid_signature(contract_factory):
    account, _, dapp = contract_factory
    hash = 1283225199545181604979924458180358646374088657288769423115053097913173815464

    signatures = []
    for sig in [signer, guardian]:
        signatures += list(sig.sign(hash))
    # new IAccount
    res = (await account.isValidSignature(hash, signatures).call()).result
    assert (res.isValid == 1)
    # old IAccount
    res = (await account.is_valid_signature(hash, signatures).call()).result
    assert (res.is_valid == 1)


async def test_support_interface(contract_factory):
    account, _, _ = contract_factory
    
    # 165
    res = (await account.supportsInterface(0x01ffc9a7).call()).result
    assert (res.success == 1)
    # IAccount
    res = (await account.supportsInterface(IACCOUNT_ID).call()).result
    assert (res.success == 1)
    # IAccount old
    res = (await account.supportsInterface(0xf10dbd44).call()).result
    assert (res.success == 1)
    # unsupported
    res = (await account.supportsInterface(0xffffffff).call()).result
    assert (res.success == 0)