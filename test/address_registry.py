import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils.Signer import Signer
from utils.utilities import deploy, str_to_felt
from utils.TransactionSender import TransactionSender

signer = Signer(123456789987654321)
guardian = Signer(456789987654321123)

VERSION = str_to_felt('0.2.3')
L1_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984

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
    account = await deploy(starknet, "contracts/ArgentDefaultAccount.cairo")
    await account.initialize(signer.public_key, guardian.public_key).invoke()
    return account

@pytest.fixture
async def registry_factory(get_starknet):
    starknet = get_starknet
    registry = await deploy(starknet, "contracts/lib/AddressRegistry.cairo")
    return registry

@pytest.mark.asyncio
async def test_initializer(account_factory):
    account = account_factory
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)
    assert (await account.get_version().call()).result.version == VERSION

@pytest.mark.asyncio
async def test_setup_registry(account_factory, registry_factory):
    account = account_factory
    registry = registry_factory
    sender = TransactionSender(account)

    assert (await registry.get_L1_address(account.contract_address).call()).result.res == 0

    await sender.send_transaction([(registry.contract_address, 'set_L1_address', [L1_ADDRESS])], [signer, guardian])

    assert (await registry.get_L1_address(account.contract_address).call()).result.res == L1_ADDRESS