import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starkware_utils.error_handling import StarkException
from utils.Signer import Signer
from utils.utilities import cached_contract, compile, str_to_felt, assert_event_emmited, update_starknet_block, reset_starknet_block, DEFAULT_TIMESTAMP
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
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
def contract_classes():
    account_cls = compile('contracts/account/ArgentAccount.cairo')
    dapp_cls = compile("contracts/test/TestDapp.cairo")

    return account_cls, dapp_cls

@pytest.fixture(scope='module')
async def contract_init(contract_classes):
    account_cls, dapp_cls = contract_classes
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
        contract_class=dapp_cls,
        constructor_calldata=[],
    )

    return starknet.state, account, account_no_guardian, dapp

@pytest.fixture
async def contract_factory(contract_classes, contract_init):
    account_cls, dapp_cls = contract_classes
    state, account, account_no_guardian, dapp = contract_init
    _state = state.copy()

    account = cached_contract(_state, account_cls, account)
    account_no_guardian = cached_contract(_state, account_cls, account_no_guardian)
    dapp = cached_contract(_state, dapp_cls, dapp)

    return account, account_no_guardian, dapp

@pytest.mark.asyncio
async def test_initializer(contract_factory):
    account, _, _ = contract_factory
    # should be configured correctly
    assert (await account.getSigner().call()).result.signer == (signer.public_key)
    assert (await account.getGuardian().call()).result.guardian == (guardian.public_key)
    assert (await account.getVersion().call()).result.version == VERSION
    assert (await account.getName().call()).result.name == NAME
    assert (await account.supportsInterface(IACCOUNT_ID).call()).result.success == 1
    # should throw when calling initialize twice
    with pytest.raises(StarkException, match="argent: already initialized"):
        await account.initialize(signer.public_key, guardian.public_key).execute()

@pytest.mark.asyncio
async def test_declare(contract_factory):
    account, _, _ = contract_factory
    sender = TransactionSender(account)

    test_cls = compile("contracts/test/StructHash.cairo")

    # should revert with only one signature
    with pytest.raises(StarkException, match="argent: signature format invalid"):
        await sender.declare_class(test_cls, [signer])

    # should revert with wrong signer
    with pytest.raises(StarkException, match="argent: signer signature invalid"):
        await sender.declare_class(test_cls, [wrong_signer, guardian])

    # should revert with wrong guardian
    with pytest.raises(StarkException, match="argent: guardian signature invalid"):
        await sender.declare_class(test_cls, [signer, wrong_guardian])

    tx_exec_info = await sender.declare_class(test_cls, [signer, guardian])

@pytest.mark.asyncio
async def test_call_dapp_with_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    calls = [(dapp.contract_address, 'set_number', [47])]

    # should revert with the wrong nonce
    with pytest.raises(StarkException) as exc_info:
        await sender.send_transaction(calls, [signer, guardian], nonce=3),
    assert exc_info.value.code == StarknetErrorCode.INVALID_TRANSACTION_NONCE

    # should revert with the wrong signer
    with pytest.raises(StarkException, match="argent: signer signature invalid"):
        await sender.send_transaction(calls, [wrong_signer, guardian])

    # should revert with the wrong guardian
    with pytest.raises(StarkException, match="argent: guardian signature invalid"):
        await sender.send_transaction(calls, [signer, wrong_guardian])

    # should revert when the signature format is not valid
    with pytest.raises(StarkException, match="argent: signature format invalid"):
        await sender.send_transaction(calls, [signer, guardian, wrong_guardian]),

    # should fail with only 1 signer
    with pytest.raises(StarkException, match="argent: signature format invalid"):
        await sender.send_transaction(calls, [signer])

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0

    tx_exec_info = await sender.send_transaction(calls, [signer, guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='transaction_executed'
    )

    assert (await dapp.get_number(account.contract_address).call()).result.number == 47

@pytest.mark.asyncio
async def test_call_dapp_guardian_backup(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # add guardian backup
    await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [guardian_backup.public_key])], [signer, guardian])

    calls = [(dapp.contract_address, 'set_number', [47])]

    # should revert with the wrong guardian
    with pytest.raises(StarkException, match="argent: guardian backup signature invalid"):
        await sender.send_transaction(calls, [signer, 0, wrong_guardian])


    # should revert when the signature format is not valid
    with pytest.raises(StarkException, match="argent: signature format invalid"):
        await sender.send_transaction(calls, [signer, guardian, guardian_backup]),

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0

    tx_exec_info = await sender.send_transaction(calls, [signer, 0, guardian_backup])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='transaction_executed'
    )

    assert (await dapp.get_number(account.contract_address).call()).result.number == 47

@pytest.mark.asyncio
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

    # should reverts calls that require the guardian to be set
    with pytest.raises(StarkException, match="argent: guardian required"):
        await sender.send_transaction([(account_no_guardian.contract_address, 'triggerEscapeGuardian', [])], [new_signer]),

    # should add a guardian
    assert (await account_no_guardian.getGuardian().call()).result.guardian == (0)
    await sender.send_transaction([(account_no_guardian.contract_address, 'changeGuardian', [new_guardian.public_key])], [new_signer])
    assert (await account_no_guardian.getGuardian().call()).result.guardian == (new_guardian.public_key)

@pytest.mark.asyncio
async def test_multicall(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # should reverts when one of the call is to the account
    with pytest.raises(StarkException):
        await sender.send_transaction([(dapp.contract_address, 'set_number', [47]), (account.contract_address, 'triggerEscapeGuardian', [])], [signer, guardian])

    with pytest.raises(StarkException):
        await sender.send_transaction([(account.contract_address, 'triggerEscapeGuardian', []), (dapp.contract_address, 'set_number', [47])], [signer, guardian])

    # should indicate which called failed
    with pytest.raises(StarkException, match="argent: multicall 1 failed"):
        await sender.send_transaction([(dapp.contract_address, 'set_number', [47]), (dapp.contract_address, 'throw_error', [1])], [signer, guardian])

    with pytest.raises(StarkException, match="argent: multicall 0 failed"):
        await sender.send_transaction([(dapp.contract_address, 'throw_error', [1]), (dapp.contract_address, 'set_number', [47])], [signer, guardian])

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction([(dapp.contract_address, 'set_number', [47]), (dapp.contract_address, 'increase_number', [10])], [signer, guardian])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 57

@pytest.mark.asyncio
async def test_change_signer(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    assert (await account.getSigner().call()).result.signer == (signer.public_key)

    # should revert with the wrong signer
    with pytest.raises(StarkException, match="argent: signer signature invalid"):
        await sender.send_transaction([(account.contract_address, 'changeSigner', [new_signer.public_key])], [wrong_signer, guardian])

    # should revert with the wrong guardian signer
    with pytest.raises(StarkException, match="argent: guardian signature invalid"):
        await sender.send_transaction([(account.contract_address, 'changeSigner', [new_signer.public_key])], [signer, wrong_guardian])

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'changeSigner', [new_signer.public_key])], [signer, guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='signer_changed',
        data=[new_signer.public_key]
    )

    assert (await account.getSigner().call()).result.signer == (new_signer.public_key)

@pytest.mark.asyncio
async def test_change_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    assert (await account.getGuardian().call()).result.guardian == (guardian.public_key)

    # should revert with the wrong signer
    with pytest.raises(StarkException, match="argent: signer signature invalid"):
        await sender.send_transaction([(account.contract_address, 'changeGuardian', [new_guardian.public_key])], [wrong_signer, guardian])

    # should revert with the wrong guardian signer
    with pytest.raises(StarkException, match="argent: guardian signature invalid"):
        await sender.send_transaction([(account.contract_address, 'changeGuardian', [new_guardian.public_key])], [signer, wrong_guardian])

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'changeGuardian', [new_guardian.public_key])], [signer, guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_changed',
        data=[new_guardian.public_key]
    )

    assert (await account.getGuardian().call()).result.guardian == (new_guardian.public_key)

@pytest.mark.asyncio
async def test_change_guardian_backup(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # should revert with the wrong signer
    with pytest.raises(StarkException, match="argent: signer signature invalid"):
        await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [new_guardian_backup.public_key])], [wrong_signer, guardian]),

    # should revert with the wrong guardian signer
    with pytest.raises(StarkException, match="argent: guardian signature invalid"):
        await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [new_guardian_backup.public_key])], [signer, wrong_guardian]),

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [new_guardian_backup.public_key])], [signer, guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_backup_changed',
        data=[new_guardian_backup.public_key]
    )

    assert (await account.getGuardianBackup().call()).result.guardianBackup == (new_guardian_backup.public_key)

@pytest.mark.asyncio
async def test_change_guardian_backup_when_no_guardian(contract_factory):
    _, account_no_guardian, dapp = contract_factory
    sender = TransactionSender(account_no_guardian)

    with pytest.raises(StarkException):
        await sender.send_transaction([(account_no_guardian.contract_address, 'changeGuardianBackup', [new_guardian_backup.public_key])], [signer])

@pytest.mark.asyncio
async def test_change_guardian_when_guardian_backup(contract_factory):
    account, _, _ = contract_factory
    sender = TransactionSender(account)

    # add guardian backup
    await sender.send_transaction([(account.contract_address, 'changeGuardianBackup', [guardian_backup.public_key])], [signer, guardian])

    with pytest.raises(StarkException, match="argent: new guardian invalid"):
        await sender.send_transaction([(account.contract_address, 'changeGuardian', [0])], [signer, guardian]),

@pytest.mark.asyncio
async def test_trigger_escape_guardian_by_signer(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # reset block_timestamp
    reset_starknet_block(state=account.state)

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'triggerEscapeGuardian', [])], [signer])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_guardian_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)

@pytest.mark.asyncio
async def test_trigger_escape_signer_by_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # reset block_timestamp
    reset_starknet_block(state=account.state)

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_signer_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

@pytest.mark.asyncio
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

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_signer_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

@pytest.mark.asyncio
async def test_escape_guardian(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # reset block_timestamp
    reset_starknet_block(state=account.state)

    # should revert when there is no escape
    with pytest.raises(StarkException, match="argent: not escaping"):
        await sender.send_transaction([(account.contract_address, 'escapeGuardian', [new_guardian.public_key])], [signer])

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'triggerEscapeGuardian', [])], [signer])

    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)

    # should fail to escape before the end of the period
    with pytest.raises(StarkException, match="argent: escape not active"):
        await sender.send_transaction([(account.contract_address, 'escapeGuardian', [new_guardian.public_key])], [signer])

    # wait security period
    update_starknet_block(state=account.state, block_timestamp=(DEFAULT_TIMESTAMP+ESCAPE_SECURITY_PERIOD))

    # should escape after the security period
    assert (await account.getGuardian().call()).result.guardian == (guardian.public_key)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'escapeGuardian', [new_guardian.public_key])], [signer])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_escaped',
        data=[new_guardian.public_key]
    )

    assert (await account.getGuardian().call()).result.guardian == (new_guardian.public_key)

    # escape should be cleared
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0 and escape.type == 0)

@pytest.mark.asyncio
async def test_escape_signer(contract_factory):
    account, _, dapp = contract_factory
    sender = TransactionSender(account)

    # reset block_timestamp
    reset_starknet_block(state=account.state)

    # should revert when there is no escape
    with pytest.raises(StarkException, match="argent: not escaping"):
        await sender.send_transaction([(account.contract_address, 'escapeSigner', [new_signer.public_key])], [guardian])

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [guardian])
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

    # should fail to escape before the end of the period
    with pytest.raises(StarkException, match="argent: escape not active"):
        await sender.send_transaction([(account.contract_address, 'escapeSigner', [new_signer.public_key])], [guardian])

    # wait security period
    update_starknet_block(state=account.state, block_timestamp=(DEFAULT_TIMESTAMP+ESCAPE_SECURITY_PERIOD))

    # should escape after the security period
    assert (await account.getSigner().call()).result.signer == (signer.public_key)
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'escapeSigner', [new_signer.public_key])], [guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='signer_escaped',
        data=[new_signer.public_key]
    )

    assert (await account.getSigner().call()).result.signer == (new_signer.public_key)

    # escape should be cleared
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0 and escape.type == 0)

@pytest.mark.asyncio
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

@pytest.mark.asyncio
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
    with pytest.raises(StarkException, match="argent: cannot override escape"):
        await sender.send_transaction([(account.contract_address, 'triggerEscapeSigner', [])], [guardian])


@pytest.mark.asyncio
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
    with pytest.raises(StarkException, match="argent: signature format invalid"):
        await sender.send_transaction([(account.contract_address, 'cancelEscape', [])], [signer]),

    # cancel escape
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'cancelEscape', [])], [signer, guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_canceled',
        data=[]
    )

    # escape should be cleared
    escape = (await account.getEscape().call()).result
    assert (escape.activeAt == 0 and escape.type == 0)

@pytest.mark.asyncio
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

@pytest.mark.asyncio
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
