import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from utils.Signer import Signer
from utils.deploy import deploy, deploy_proxy
from utils.TransactionSender import TransactionSender

signer = Signer(123456789987654321)
guardian = Signer(456789987654321123)

VERSION = 206933470768 # '0.2.0' = 30 2E 32 2E 30 = 0x302E322E30 = 206933470768

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
    account_impl = await deploy(starknet, "contracts/ArgentAccount.cairo")
    account_proxy = await deploy_proxy(starknet, "contracts/Proxy.cairo", "contracts/ArgentAccount.cairo", [account_impl.contract_address])
    await account_proxy.initialize(signer.public_key, guardian.public_key).invoke()
    return account_proxy

@pytest.fixture
async def dapp_factory(get_starknet):
    starknet = get_starknet
    dapp = await deploy(starknet, "contracts/TestDapp.cairo")
    return dapp

@pytest.mark.asyncio
async def test_initializer(account_factory):
    account = account_factory
    assert (await account.get_signer().call()).result.signer == (signer.public_key)
    assert (await account.get_guardian().call()).result.guardian == (guardian.public_key)
    assert (await account.get_version().call()).result.version == VERSION

@pytest.mark.asyncio
async def test_call_dapp(account_factory, dapp_factory):
    account = account_factory
    dapp = dapp_factory
    sender = TransactionSender(account)

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction(dapp.contract_address, 'set_number', [47], [signer, guardian])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47