import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.testing.objects import StarknetContractCall
from starkware.starknet.public.abi import get_selector_from_name
from utils.Signer import Signer
from utils.deploy import deploy
from utils.TransactionBuilder import TransactionBuilder

signer = Signer(123456789987654321)
guardian = Signer(456789987654321123)
L1_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984

ESCAPE_SECURITY_PERIOD = 500
MAGIC_VALUE = 1138073982574099226972715907883430523600275391887289231447128254784345409857

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
    account = await deploy(starknet, "contracts/ArgentAccount.cairo", [signer.public_key, guardian.public_key, L1_ADDRESS])
    await account.set_self_address(account.contract_address).invoke()
    return starknet, account

@pytest.mark.asyncio
async def test_initializer(account_factory):
    _, account = account_factory
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)
    assert (await account.get_L1_address().call()).result.L1_address == (L1_ADDRESS)

@pytest.mark.asyncio
async def test_execute(account_factory):
    starknet, account = account_factory
    dapp = await deploy(starknet, "contracts/TestDapp.cairo")
    builder = TransactionBuilder(account, signer, guardian)

    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_execute_transaction(dapp.contract_address, 'set_number', [47], nonce)
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await transaction.invoke(signature=signatures)
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47

@pytest.mark.asyncio
async def test_execute_no_guardian(account_factory):
    starknet, account = account_factory
    account_no_guardian = await deploy(starknet, "contracts/ArgentAccount.cairo", [signer.public_key, 0, L1_ADDRESS])
    await account_no_guardian.set_self_address(account_no_guardian.contract_address).invoke()
    dapp = await deploy(starknet, "contracts/TestDapp.cairo")
    builder = TransactionBuilder(account_no_guardian, signer, 0)

    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_execute_transaction(dapp.contract_address, 'set_number', [47], nonce)

    assert (await dapp.get_number(account_no_guardian.contract_address).call()).result.number == 0
    await transaction.invoke(signature=signatures)
    assert (await dapp.get_number(account_no_guardian.contract_address).call()).result.number == 47

@pytest.mark.asyncio
async def test_change_signer(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    new_signer = Signer(4444444444)
    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_change_signer_transaction(new_signer.public_key, nonce)

    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    await transaction.invoke(signature=signatures)
    assert (await account.get_signer().call()).result.signer == (new_signer.public_key)

@pytest.mark.asyncio
async def test_change_guardian(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    new_guardian = Signer(55555555)
    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_change_guardian_transaction(new_guardian.public_key, nonce)

    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)
    await transaction.invoke(signature=signatures)
    assert (await account.get_guardian().call()).result.guardian == (new_guardian.public_key)

@pytest.mark.asyncio
async def test_change_L1_address(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    new_L1_address = 0xa1a1224e9071470ab12a8df7626d4fe7789a039d
    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_change_L1_address_transaction(new_L1_address, nonce)

    assert (await account.get_L1_address().call()).result.L1_address == (L1_ADDRESS)
    await transaction.invoke(signature=signatures)
    assert (await account.get_L1_address().call()).result.L1_address == (new_L1_address)

@pytest.mark.asyncio
async def test_trigger_escape_by_signer(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    await builder.set_block_timestamp(121)

    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_trigger_escape_transaction(signer, nonce)
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)
    await transaction.invoke(signature=signatures)
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (121 + ESCAPE_SECURITY_PERIOD) and escape.caller == signer.public_key)

@pytest.mark.asyncio
async def test_trigger_escape_by_guardian(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    await builder.set_block_timestamp(127)

    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_trigger_escape_transaction(guardian, nonce)
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)
    await transaction.invoke(signature=signatures)
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == guardian.public_key)

@pytest.mark.asyncio
async def test_escape_guardian(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    await builder.set_block_timestamp(121)

    # trigger escape
    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_trigger_escape_transaction(signer, nonce)
    await transaction.invoke(signature=signatures)
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (121 + ESCAPE_SECURITY_PERIOD) and escape.caller == signer.public_key)

    await builder.set_block_timestamp(121 + ESCAPE_SECURITY_PERIOD)

    # escape guardian
    new_guardian = Signer(55555555)
    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_escape_guardian_transaction(new_guardian, nonce)
    
    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)
    await transaction.invoke(signature=signatures)
    assert (await account.get_guardian().call()).result.guardian == (new_guardian.public_key)
    # escape should be cleared
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)

@pytest.mark.asyncio
async def test_escape_signer(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    await builder.set_block_timestamp(121)

    # trigger escape
    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_trigger_escape_transaction(guardian, nonce)
    await transaction.invoke(signature=signatures)
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (121 + ESCAPE_SECURITY_PERIOD) and escape.caller == guardian.public_key)

    await builder.set_block_timestamp(121 + ESCAPE_SECURITY_PERIOD + 1)

    # escape signer
    new_signer = Signer(555554675)
    nonce = await builder.get_nonce()
    (transaction, signatures) = builder.build_escape_signer_transaction(new_signer, nonce)
    
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    await transaction.invoke(signature=signatures)
    assert (await account.get_signer().call()).result.signer == (new_signer.public_key)
    # escape should be cleared
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == 0 and escape.caller == 0)

@pytest.mark.asyncio
async def test_is_valid_signature(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    hash = 1283225199545181604979924458180358646374088657288769423115053097913173815464
    transaction = builder.build_is_valid_signature_transaction(hash)
    res = (await transaction.call()).result
    assert (res.magic_value == MAGIC_VALUE)
