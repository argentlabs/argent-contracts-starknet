import pytest
import asyncio
import logging
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starknet.business_logic.state import BlockInfo
from starkware.starknet.business_logic.transaction_execution_objects import Event
from starkware.starknet.compiler.compile import get_selector_from_name
from utils.Signer import Signer
from utils.utilities import deploy, assert_revert, str_to_felt, assert_event_emmited
from utils.TransactionSender import TransactionSender

LOGGER = logging.getLogger(__name__)

signer = Signer(123456789987654321)
guardian = Signer(456789987654321123)
guardian_backup = Signer(354523164513454)

wrong_signer = Signer(666666666666666666)
wrong_guardian = Signer(6767676767)

DEFAULT_TIMESTAMP = 1640991600
ESCAPE_SECURITY_PERIOD = 24*7*60*60

VERSION = str_to_felt('0.2.0')

ESCAPE_TYPE_GUARDIAN = 0
ESCAPE_TYPE_SIGNER = 1

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet

def update_starknet_block(starknet, block_number=1, block_timestamp=DEFAULT_TIMESTAMP):
    starknet.state.state.block_info = BlockInfo(block_number=block_number, block_timestamp=block_timestamp)

def reset_starknet_block(starknet):
    update_starknet_block(starknet=starknet)

@pytest.fixture
async def account_factory(get_starknet):
    starknet = get_starknet
    account = await deploy(starknet, "contracts/ArgentAccount.cairo", [signer.public_key, guardian.public_key])
    return account

@pytest.fixture
async def dapp_factory(get_starknet):
    starknet = get_starknet
    dapp = await deploy(starknet, "contracts/test/TestDapp.cairo")
    return dapp

@pytest.mark.asyncio
async def test_initializer(account_factory):
    account = account_factory
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)
    assert (await account.get_version().call()).result.version == VERSION

@pytest.mark.asyncio
async def test_call_dapp_with_guardian(account_factory, dapp_factory):
    account = account_factory
    dapp = dapp_factory
    sender = TransactionSender(account)

    calls = [(dapp.contract_address, 'set_number', [47])]

    # should revert with the wrong nonce
    await assert_revert(
        sender.send_transaction(calls, [signer, guardian], nonce=3)
    )

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction(calls, [wrong_signer, guardian])
    )

    # should revert with the wrong guardian
    await assert_revert(
        sender.send_transaction(calls, [signer, wrong_guardian])
    )

    # should fail with only 1 signer
    await assert_revert(
        sender.send_transaction(calls, [signer])
    )

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction(calls, [signer, guardian])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47

@pytest.mark.asyncio
async def test_call_dapp_no_guardian(get_starknet, dapp_factory):
    starknet = get_starknet
    account_no_guardian = await deploy(starknet, "contracts/ArgentAccount.cairo", [signer.public_key, 0])
    dapp = dapp_factory
    sender = TransactionSender(account_no_guardian)

    # should call the dapp
    assert (await dapp.get_number(account_no_guardian.contract_address).call()).result.number == 0
    await sender.send_transaction([(dapp.contract_address, 'set_number', [47])], [signer])
    assert (await dapp.get_number(account_no_guardian.contract_address).call()).result.number == 47

    # should change the signer
    new_signer = Signer(4444444444)
    assert (await account_no_guardian.get_signer().call()).result.signer == (signer.public_key)
    await sender.send_transaction([(account_no_guardian.contract_address, 'change_signer', [new_signer.public_key])], [signer])
    assert (await account_no_guardian.get_signer().call()).result.signer == (new_signer.public_key)

    # should reverts calls that require the guardian to be set
    await assert_revert(
        sender.send_transaction([(account_no_guardian.contract_address, 'trigger_escape_guardian', [])], [signer])
    )

    # should add a guardian
    new_guardian = Signer(34567788966)
    assert (await account_no_guardian.get_guardian().call()).result.guardian == (0)
    await sender.send_transaction([(account_no_guardian.contract_address, 'change_guardian', [new_guardian.public_key])], [new_signer])
    assert (await account_no_guardian.get_guardian().call()).result.guardian == (new_guardian.public_key)

@pytest.mark.asyncio
async def test_multicall(account_factory, dapp_factory):
    account = account_factory
    dapp = dapp_factory
    sender = TransactionSender(account)

    # should reverts when one of the call is to the account
    await assert_revert(
        sender.send_transaction([(dapp.contract_address, 'set_number', [47]), (account.contract_address, 'trigger_escape_guardian', [])], [signer, guardian])
    )
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'trigger_escape_guardian', []), (dapp.contract_address, 'set_number', [47])], [signer, guardian])
    )

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction([(dapp.contract_address, 'set_number', [47]), (dapp.contract_address, 'increase_number', [10])], [signer, guardian])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 57

@pytest.mark.asyncio
async def test_change_signer(account_factory):
    account = account_factory
    sender = TransactionSender(account)
    new_signer = Signer(4444444444)

    assert (await account.get_signer().call()).result.signer == (signer.public_key)

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'change_signer', [new_signer.public_key])], [wrong_signer, guardian])
    )

    # should revert with the wrong guardian signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'change_signer', [new_signer.public_key])], [signer, wrong_guardian])
    )

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'change_signer', [new_signer.public_key])], [signer, guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='signer_changed',
        data=[new_signer.public_key]
    )

    assert (await account.get_signer().call()).result.signer == (new_signer.public_key)

@pytest.mark.asyncio
async def test_change_guardian(account_factory):
    account = account_factory
    sender = TransactionSender(account)
    new_guardian = Signer(55555555)

    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'change_guardian', [new_guardian.public_key])], [wrong_signer, guardian])
    )

    # should revert with the wrong guardian signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'change_guardian', [new_guardian.public_key])], [signer, wrong_guardian])
    )

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'change_guardian', [new_guardian.public_key])], [signer, guardian])
    
    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_changed',
        data=[new_guardian.public_key]
    )

    assert (await account.get_guardian().call()).result.guardian == (new_guardian.public_key)

@pytest.mark.asyncio
async def test_change_guardian_backup(account_factory):
    account = account_factory
    sender = TransactionSender(account)
    new_guardian_backup = Signer(55555555)

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'change_guardian_backup', [new_guardian_backup.public_key])], [wrong_signer, guardian])
    )

    # should revert with the wrong guardian signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'change_guardian_backup', [new_guardian_backup.public_key])], [signer, wrong_guardian])
    )

    # should work with the correct signers
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'change_guardian_backup', [new_guardian_backup.public_key])], [signer, guardian])
    
    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_backup_changed',
        data=[new_guardian_backup.public_key]
    )

    assert (await account.get_guardian_backup().call()).result.guardian_backup == (new_guardian_backup.public_key)

@pytest.mark.asyncio
async def test_change_guardian_backup_when_no_guardian(get_starknet):
    starknet = get_starknet
    account = await deploy(starknet, "contracts/ArgentAccount.cairo", [signer.public_key, 0])
    sender = TransactionSender(account)
    new_guardian_backup = Signer(55555555)

    await assert_revert(
        sender.send_transaction([(account.contract_address, 'change_guardian_backup', [new_guardian_backup.public_key])], [signer])
    )

@pytest.mark.asyncio
async def test_trigger_escape_guardian_by_signer(get_starknet, account_factory):
    account = account_factory
    starknet = get_starknet
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(starknet=starknet)

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'trigger_escape_guardian', [])], [signer])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_guardian_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)

@pytest.mark.asyncio
async def test_trigger_escape_signer_by_guardian(get_starknet, account_factory):
    account = account_factory
    starknet = get_starknet
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(starknet=starknet)

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'trigger_escape_signer', [])], [guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_signer_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

@pytest.mark.asyncio
async def test_trigger_escape_signer_by_guardian_backup(get_starknet, account_factory):
    account = account_factory
    starknet = get_starknet
    sender = TransactionSender(account)
    await sender.send_transaction([(account.contract_address, 'change_guardian_backup', [guardian_backup.public_key])], [signer, guardian])
    
    # reset block_timestamp
    reset_starknet_block(starknet=starknet)

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0)

    tx_exec_info = await sender.send_transaction([(account.contract_address, 'trigger_escape_signer', [])], [0, guardian_backup])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_signer_triggered',
        data=[DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD]
    )

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

@pytest.mark.asyncio
async def test_escape_guardian(get_starknet, account_factory):
    account = account_factory
    starknet = get_starknet
    sender = TransactionSender(account)
    new_guardian = Signer(55555555)

    # reset block_timestamp
    reset_starknet_block(starknet=starknet)

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'trigger_escape_guardian', [])], [signer])

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)

    # should fail to escape before the end of the period
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'escape_guardian', [new_guardian.public_key])], [signer])
    )

    # wait security period
    update_starknet_block(starknet=starknet, block_timestamp=(DEFAULT_TIMESTAMP+ESCAPE_SECURITY_PERIOD))

    # should escape after the security period
    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)
    
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'escape_guardian', [new_guardian.public_key])], [signer])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='guardian_escaped',
        data=[new_guardian.public_key]
    )

    assert (await account.get_guardian().call()).result.guardian == (new_guardian.public_key)

    # escape should be cleared
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.type == 0)

@pytest.mark.asyncio
async def test_escape_signer(get_starknet, account_factory):
    account = account_factory
    starknet = get_starknet
    sender = TransactionSender(account)
    new_signer = Signer(5555555578895)
    
    # reset block_timestamp
    reset_starknet_block(starknet=starknet)

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'trigger_escape_signer', [])], [guardian])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

    # should fail to escape before the end of the period
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'escape_signer', [new_signer.public_key])], [guardian])
    )

    # wait security period
    update_starknet_block(starknet=starknet, block_timestamp=(DEFAULT_TIMESTAMP+ESCAPE_SECURITY_PERIOD))

    # should escape after the security period
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'escape_signer', [new_signer.public_key])], [guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='signer_escaped',
        data=[new_signer.public_key]
    )

    assert (await account.get_signer().call()).result.signer == (new_signer.public_key)

    # escape should be cleared
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.type == 0)

@pytest.mark.asyncio
async def test_signer_overrides_trigger_escape_signer(get_starknet, account_factory):
    account = account_factory
    starknet = get_starknet
    sender = TransactionSender(account)
    new_signer = Signer(5555555578895)
    
    # reset block_timestamp
    reset_starknet_block(starknet=starknet)

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'trigger_escape_signer', [])], [guardian])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

    # wait few seconds
    update_starknet_block(starknet=starknet, block_timestamp=(DEFAULT_TIMESTAMP+100))

    # signer overrides escape
    await sender.send_transaction([(account.contract_address, 'trigger_escape_guardian', [])], [signer])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + 100 + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)

@pytest.mark.asyncio
async def test_guardian_overrides_trigger_escape_guardian(get_starknet, account_factory):
    account = account_factory
    starknet = get_starknet
    sender = TransactionSender(account)
    new_signer = Signer(5555555578895)
    
    # reset block_timestamp
    reset_starknet_block(starknet=starknet)

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'trigger_escape_guardian', [])], [signer])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_GUARDIAN)

    # wait few seconds
    update_starknet_block(starknet=starknet, block_timestamp=(DEFAULT_TIMESTAMP+100))

    # guradian tries to override escape => should fail
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'trigger_escape_signer', [])], [guardian])
    )


@pytest.mark.asyncio
async def test_cancel_escape(get_starknet, account_factory):
    account = account_factory
    starknet = get_starknet
    sender = TransactionSender(account)
    
    # reset block_timestamp
    reset_starknet_block(starknet=starknet)

    # trigger escape
    await sender.send_transaction([(account.contract_address, 'trigger_escape_signer', [])], [guardian])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (DEFAULT_TIMESTAMP + ESCAPE_SECURITY_PERIOD) and escape.type == ESCAPE_TYPE_SIGNER)

    # should fail to cancel with only the signer
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'cancel_escape', [])], [signer])
    )

    # cancel escape
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'cancel_escape', [])], [signer, guardian])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='escape_canceled',
        data=[]
    )

    # escape should be cleared
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.type == 0)

@pytest.mark.asyncio
async def test_is_valid_signature(account_factory):
    account = account_factory
    hash = 1283225199545181604979924458180358646374088657288769423115053097913173815464

    signatures = []
    for sig in [signer, guardian]:
        signatures += list(sig.sign(hash))
    
    await account.is_valid_signature(hash, signatures).call()