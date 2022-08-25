import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils.Signer import Signer
from utils.utilities import cached_contract, compile
from utils.TransactionSender import TransactionSender

signer = Signer(1)

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
def contract_classes():
    account_cls = compile('contracts/ArgentPluginAccount.cairo')
    plugin_cls = compile("contracts/plugins/SessionKey.cairo")
    
    return account_cls, plugin_cls

@pytest.fixture(scope='module')
async def contract_init(contract_classes):
    account_cls, plugin_cls = contract_classes
    starknet = await Starknet.empty()

    account = await starknet.deploy(
        contract_class=account_cls,
        constructor_calldata=[]
    )
    await account.initialize(signer.public_key, 0).invoke()

    plugin_cls_hash = await starknet.declare(contract_class=plugin_cls)

    return starknet.state, account, plugin_cls_hash.class_hash

@pytest.fixture
def contract_factory(contract_classes, contract_init):
    account_cls, plugin_cls = contract_classes
    state, account, plugin_class = contract_init
    _state = state.copy()
    account = cached_contract(_state, account_cls, account)

    return account, plugin_class

@pytest.mark.asyncio
async def test_add_plugin(contract_factory):
    account, plugin = contract_factory
    sender = TransactionSender(account)

    assert (await account.is_plugin(plugin).call()).result.success == (0)
    await sender.send_transaction([(account.contract_address, 'add_plugin', [plugin])], [signer])
    assert (await account.is_plugin(plugin).call()).result.success == (1)

@pytest.mark.asyncio
async def test_remove_plugin(contract_factory):
    account, plugin = contract_factory
    sender = TransactionSender(account)

    assert (await account.is_plugin(plugin).call()).result.success == (0)
    await sender.send_transaction([(account.contract_address, 'add_plugin', [plugin])], [signer])
    assert (await account.is_plugin(plugin).call()).result.success == (1)
    await sender.send_transaction([(account.contract_address, 'remove_plugin', [plugin])], [signer])
    assert (await account.is_plugin(plugin).call()).result.success == (0)