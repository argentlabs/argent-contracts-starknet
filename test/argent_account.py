import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.public.abi import get_selector_from_name
from utils.Signer import Signer
from utils.deploy import deploy
from utils.TransactionBuilder import TransactionBuilder

signer = Signer(123456789987654321)
guardian = Signer(456789987654321123)
L1_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984

ESCAPE_SECURITY_PERIOD = 500


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
    account = await deploy(starknet, "contracts/ArgentAccount.cairo")
    print('account address ', account.contract_address)
    await account.initialize(signer.public_key, guardian.public_key, L1_ADDRESS, account.contract_address).invoke()
    return starknet, account


# @pytest.mark.asyncio
# async def test_initializer(account_factory):
#     _, account = account_factory
#     assert (await account.get_signer().call()).signer == (signer.public_key)
#     assert (await account.get_guardian().call()).guardian == (guardian.public_key)
#     assert (await account.get_L1_address().call()).L1_address == (L1_ADDRESS)


# @pytest.mark.asyncio
# async def test_execute(account_factory):
#     starknet, account = account_factory
#     initializable = await deploy(starknet, "contracts/Initializable.cairo")

#     builder = TransactionBuilder(account, signer, guardian)
#     nonce = await builder.get_current_nonce()
#     transaction = builder.build_execute_transaction(initializable.contract_address, 'initialize', [], nonce)

#     assert await initializable.initialized().call() == (0,)
#     await transaction.invoke()
#     assert await initializable.initialized().call() == (1,)

# @pytest.mark.asyncio
# async def test_change_signer(account_factory):
#     starknet, account = account_factory
#     builder = TransactionBuilder(account, signer, guardian)

#     new_signer = Signer(4444444444)
#     nonce = await builder.get_current_nonce()
#     transaction = builder.build_change_signer_transaction(new_signer.public_key, nonce)

#     assert (await account.get_signer().call()).signer == (signer.public_key)
#     await transaction.invoke()
#     assert (await account.get_signer().call()).signer == (new_signer.public_key)

# @pytest.mark.asyncio
# async def test_change_guardian(account_factory):
#     starknet, account = account_factory
#     builder = TransactionBuilder(account, signer, guardian)

#     new_guardian = Signer(55555555)
#     nonce = await builder.get_current_nonce()
#     transaction = builder.build_change_guardian_transaction(new_guardian.public_key, nonce)

#     assert (await account.get_guardian().call()).guardian == (guardian.public_key)
#     await transaction.invoke()
#     assert (await account.get_guardian().call()).guardian == (new_guardian.public_key)

@pytest.mark.asyncio
async def test_trigger_escape_signer(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    await builder.set_block_timestamp(121)

    nonce = await builder.get_current_nonce()
    transaction = builder.build_trigger_escape_transaction(signer, nonce)
    escape = await account.get_escape().call()
    assert (escape.active_at == 0 and escape.caller == 0)
    await transaction.invoke()
    escape = await account.get_escape().call()
    assert (escape.active_at == (121 + ESCAPE_SECURITY_PERIOD) and escape.caller == signer.public_key)

@pytest.mark.asyncio
async def test_trigger_escape_guardian(account_factory):
    starknet, account = account_factory
    builder = TransactionBuilder(account, signer, guardian)

    await builder.set_block_timestamp(127)

    nonce = await builder.get_current_nonce()
    transaction = builder.build_trigger_escape_transaction(guardian, nonce)
    escape = await account.get_escape().call()
    assert (escape.active_at == 0 and escape.caller == 0)
    await transaction.invoke()
    escape = await account.get_escape().call()
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == guardian.public_key)