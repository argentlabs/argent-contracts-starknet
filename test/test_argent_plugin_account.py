import pytest
import asyncio

from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.testing.starknet import Starknet
from utils.Signer import Signer
from utils.utilities import cached_contract, assert_revert
from utils.TransactionSender import TransactionSender

signer = Signer(1)


@pytest.fixture(scope='module')
async def contract_init(starknet: Starknet, plugin_account_cls: ContractClass, session_plugin_cls: ContractClass):
    account = await starknet.deploy(
        contract_class=plugin_account_cls,
        constructor_calldata=[]
    )
    await account.initialize(signer.public_key, 0).execute()

    plugin_cls_hash = await starknet.declare(contract_class=session_plugin_cls)

    return starknet.state, account, plugin_cls_hash.class_hash


@pytest.fixture
def contract_factory(plugin_account_cls: ContractClass, session_plugin_cls: ContractClass, contract_init):
    state, account, plugin_class = contract_init
    _state = state.copy()
    account = cached_contract(_state, plugin_account_cls, account)

    return account, plugin_class


async def test_add_plugin(contract_factory):
    account, plugin = contract_factory
    sender = TransactionSender(account)

    # should fail when the plugin is 0
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'addPlugin', [0])], [signer]),
        "argent: plugin invalid"
    )

    assert (await account.isPlugin(plugin).call()).result.success == (0)
    await sender.send_transaction([(account.contract_address, 'addPlugin', [plugin])], [signer])
    assert (await account.isPlugin(plugin).call()).result.success == (1)


async def test_remove_plugin(contract_factory):
    account, plugin = contract_factory
    sender = TransactionSender(account)

    assert (await account.isPlugin(plugin).call()).result.success == 0
    await sender.send_transaction([(account.contract_address, 'addPlugin', [plugin])], [signer])
    assert (await account.isPlugin(plugin).call()).result.success == 1

    # should fail when the plugin is unknown
    await assert_revert(
        sender.send_transaction([(account.contract_address, 'removePlugin', [1234])], [signer]),
        "argent: unknown plugin"
    )

    await sender.send_transaction([(account.contract_address, 'removePlugin', [plugin])], [signer])
    assert (await account.isPlugin(plugin).call()).result.success == 0