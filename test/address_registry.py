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

VERSION = 206933405232 # '0.1.0' = 30 2E 31 2E 30 = 0x302E312E30 = 206933405232

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
    account = await deploy(starknet, "contracts/ArgentAccount.cairo", [signer.public_key, guardian.public_key])
    return starknet, account

@pytest.mark.asyncio
async def test_initializer(account_factory):
    _, account = account_factory
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)
    assert (await account.get_version().call()).result.version == VERSION