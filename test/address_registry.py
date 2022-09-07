import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils.Signer import Signer
from utils.utilities import compile, cached_contract
from utils.TransactionSender import TransactionSender

signer = Signer(123456789987654321)
guardian = Signer(456789987654321123)

L1_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
def contract_classes():
    account_cls = compile('contracts/account/ArgentAccount.cairo')
    registry_cls = compile("contracts/lib/AddressRegistry.cairo")
    
    return account_cls, registry_cls

@pytest.fixture(scope='module')
async def contract_init(contract_classes):
    account_cls, registry_cls = contract_classes
    starknet = await Starknet.empty()

    account = await starknet.deploy(
        contract_class=account_cls,
        constructor_calldata=[]
    )
    await account.initialize(signer.public_key, guardian.public_key).execute()

    registry = await starknet.deploy(
        contract_class=registry_cls,
        constructor_calldata=[]
    )

    return starknet.state, account, registry

@pytest.fixture
def contract_factory(contract_classes, contract_init):
    account_cls, registry_cls = contract_classes
    state, account, registry = contract_init
    _state = state.copy()
    account = cached_contract(_state, account_cls, account)
    registry = cached_contract(_state, registry_cls, registry)

    return account, registry

@pytest.mark.asyncio
async def test_setup_registry(contract_factory):
    account, registry = contract_factory
    sender = TransactionSender(account)

    assert (await registry.get_L1_address(account.contract_address).call()).result.res == 0

    await sender.send_transaction([(registry.contract_address, 'set_L1_address', [L1_ADDRESS])], [signer, guardian])

    assert (await registry.get_L1_address(account.contract_address).call()).result.res == L1_ADDRESS