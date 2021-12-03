import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from utils.Signer import Signer
from utils.deploy import deploy
from utils.TransactionSender import TransactionSender

signer = Signer(123456789987654321)
guardian_signer = Signer(456789987654321123)

wrong_signer = Signer(666666666666666666)
wrong_guardian_signer = Signer(6767676767)

ESCAPE_SECURITY_PERIOD = 500
VERSION = 206933405232 # '0.1.0' = 30 2E 31 2E 30 = 0x302E312E30 = 206933405232

async def assert_revert(expression):
    try:
        await expression
        assert False
    except StarkException as err:
        _, error = err.args
        assert error['code'] == StarknetErrorCode.TRANSACTION_FAILED

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet

@pytest.fixture
async def account_factory(get_starknet):
    starknet = get_starknet
    guardian = await deploy(starknet, "contracts/guardians/SCSKGuardian.cairo", [guardian_signer.public_key])
    account = await deploy(starknet, "contracts/ArgentAccount.cairo", [signer.public_key, guardian.contract_address])
    return account, guardian

@pytest.fixture
async def dapp_factory(get_starknet):
    starknet = get_starknet
    dapp = await deploy(starknet, "contracts/TestDapp.cairo")
    return dapp

@pytest.mark.asyncio
async def test_initializer(account_factory):
    account, guardian = account_factory
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    assert (await account.get_guardian().call()).result.guardian == (guardian.contract_address)
    assert (await account.get_version().call()).result.version == VERSION

@pytest.mark.asyncio
async def test_call_dapp_with_guardian(account_factory, dapp_factory):
    account, _ = account_factory
    dapp = dapp_factory
    sender = TransactionSender(account)

    # should revert with the wrong nonce
    await assert_revert(
        sender.send_transaction(dapp.contract_address, 'set_number', [47], [signer, guardian_signer], nonce=3)
    )

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction(dapp.contract_address, 'set_number', [47], [wrong_signer, guardian_signer])
    )

    # should revert with the wrong guardian key
    await assert_revert(
        sender.send_transaction(dapp.contract_address, 'set_number', [47], [signer, wrong_guardian_signer])
    )

    # should fail with only 1 signer
    await assert_revert(
        sender.send_transaction(dapp.contract_address, 'set_number', [47], [signer])
    )

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction(dapp.contract_address, 'set_number', [47], [signer, guardian_signer])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47

@pytest.mark.asyncio
async def test_call_dapp_no_guardian(get_starknet, dapp_factory):
    starknet = get_starknet
    account_no_guardian = await deploy(starknet, "contracts/ArgentAccount.cairo", [signer.public_key, 0])
    dapp = dapp_factory
    sender = TransactionSender(account_no_guardian)

    # should call the dapp
    assert (await dapp.get_number(account_no_guardian.contract_address).call()).result.number == 0
    await sender.send_transaction(dapp.contract_address, 'set_number', [47], [signer])
    assert (await dapp.get_number(account_no_guardian.contract_address).call()).result.number == 47

    # should change the signer
    new_signer = Signer(4444444444)
    assert (await account_no_guardian.get_signer().call()).result.signer == (signer.public_key)
    await sender.send_transaction(account_no_guardian.contract_address, 'change_signer', [new_signer.public_key], [signer])
    assert (await account_no_guardian.get_signer().call()).result.signer == (new_signer.public_key)

    # should reverts calls that require the guardian to be set
    await assert_revert(
        sender.send_transaction(account_no_guardian.contract_address, 'trigger_escape_guardian', [], [signer])
    )

    # should add a guardian
    new_guardian = Signer(34567788966)
    assert (await account_no_guardian.get_guardian().call()).result.guardian == (0)
    await sender.send_transaction(account_no_guardian.contract_address, 'change_guardian', [new_guardian.public_key], [new_signer])
    assert (await account_no_guardian.get_guardian().call()).result.guardian == (new_guardian.public_key)

@pytest.mark.asyncio
async def test_change_signer(account_factory):
    account, _ = account_factory
    sender = TransactionSender(account)
    new_signer = Signer(4444444444)

    assert (await account.get_signer().call()).result.signer == (signer.public_key)

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction(account.contract_address, 'change_signer', [new_signer.public_key], [wrong_signer, guardian_signer])
    )

    # should revert with the wrong guardian signer
    await assert_revert(
        sender.send_transaction(account.contract_address, 'change_signer', [new_signer.public_key], [signer, wrong_guardian_signer])
    )

    # should work with the correct signers
    await sender.send_transaction(account.contract_address, 'change_signer', [new_signer.public_key], [signer, guardian_signer])

    assert (await account.get_signer().call()).result.signer == (new_signer.public_key)

@pytest.mark.asyncio
async def test_change_guardian(account_factory):
    account, guardian = account_factory
    sender = TransactionSender(account)
    new_guardian = Signer(55555555)

    assert (await account.get_guardian().call()).result.guardian == (guardian.contract_address)

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction(account.contract_address, 'change_guardian', [new_guardian.public_key], [wrong_signer, guardian_signer])
    )

    # should revert with the wrong guardian signer
    await assert_revert(
        sender.send_transaction(account.contract_address, 'change_guardian', [new_guardian.public_key], [signer, wrong_guardian_signer])
    )

    # should work with the correct signers
    await sender.send_transaction(account.contract_address, 'change_guardian', [new_guardian.public_key], [signer, guardian_signer])

    assert (await account.get_guardian().call()).result.guardian == (new_guardian.public_key)

@pytest.mark.asyncio
async def test_trigger_escape_guardian(account_factory):
    account, _ = account_factory
    sender = TransactionSender(account)
    await sender.set_block_timestamp(127)

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)

    await sender.send_transaction(account.contract_address, 'trigger_escape_guardian', [], [signer])

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == signer.public_key)

@pytest.mark.asyncio
async def test_trigger_escape_signer(account_factory):
    account, guardian = account_factory
    sender = TransactionSender(account)
    await sender.set_block_timestamp(127)

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)

    await sender.send_transaction(account.contract_address, 'trigger_escape_signer', [], [guardian_signer])

    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == guardian.contract_address)

@pytest.mark.asyncio
async def test_escape_guardian(account_factory):
    account, guardian = account_factory
    sender = TransactionSender(account)
    new_guardian = Signer(55555555)
    await sender.set_block_timestamp(127)

    # trigger escape
    await sender.send_transaction(account.contract_address, 'trigger_escape_guardian', [], [signer])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == signer.public_key)

    # should fail to escape before the end of the period
    await assert_revert(
        sender.send_transaction(account.contract_address, 'escape_guardian', [new_guardian.public_key], [signer])
    )

    # wait security period
    await sender.set_block_timestamp(127 + ESCAPE_SECURITY_PERIOD)

    # should escape after the security period
    assert (await account.get_guardian().call()).result.guardian == (guardian.contract_address)
    await sender.send_transaction(account.contract_address, 'escape_guardian', [new_guardian.public_key], [signer])
    assert (await account.get_guardian().call()).result.guardian == (new_guardian.public_key)

    # escape should be cleared
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)

@pytest.mark.asyncio
async def test_escape_signer(account_factory):
    account, guardian = account_factory
    sender = TransactionSender(account)
    new_signer = Signer(5555555578895)
    await sender.set_block_timestamp(127)

    # trigger escape
    await sender.send_transaction(account.contract_address, 'trigger_escape_signer', [], [guardian_signer])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == guardian.contract_address)

    # should fail to escape before the end of the period
    await assert_revert(
        sender.send_transaction(account.contract_address, 'escape_signer', [new_signer.public_key], [guardian_signer])
    )

    # wait security period
    await sender.set_block_timestamp(127 + ESCAPE_SECURITY_PERIOD)

    # should escape after the security period
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    await sender.send_transaction(account.contract_address, 'escape_signer', [new_signer.public_key], [guardian_signer])
    assert (await account.get_signer().call()).result.signer == (new_signer.public_key)

    # escape should be cleared
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)

@pytest.mark.asyncio
async def test_cancel_escape(account_factory):
    account, guardian = account_factory
    sender = TransactionSender(account)
    await sender.set_block_timestamp(127)

    # trigger escape
    await sender.send_transaction(account.contract_address, 'trigger_escape_signer', [], [guardian_signer])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == guardian.contract_address)

    # should fail to cancel with only the signer
    await assert_revert(
        sender.send_transaction(account.contract_address, 'cancel_escape', [], [signer])
    )

    # cancel escape
    await sender.send_transaction(account.contract_address, 'cancel_escape', [], [signer, guardian_signer])

    # escape should be cleared
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)

@pytest.mark.asyncio
async def test_is_valid_signature(account_factory):
    account, guardian = account_factory
    hash = 1283225199545181604979924458180358646374088657288769423115053097913173815464

    signatures = []
    for sig in [signer, guardian_signer]:
        signatures += list(sig.sign(hash))
    
    await account.is_valid_signature(hash, signatures).call()