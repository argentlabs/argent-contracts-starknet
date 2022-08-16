import pytest
import asyncio
import logging
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.business_logic.state.state import BlockInfo
from utils.Signer import Signer
from utils.utilities import deploy, declare, assert_revert, str_to_felt, assert_event_emmited
from utils.TransactionSender import TransactionSender
from starkware.cairo.common.hash_state import compute_hash_on_elements
from starkware.starknet.compiler.compile import get_selector_from_name
from utils.merkle_utils import generate_merkle_proof, generate_merkle_root, get_leaves, verify_merkle_proof


LOGGER = logging.getLogger(__name__)

signer = Signer(123456789987654321)

session_key = Signer(666666666666666666)
wrong_session_key = Signer(6767676767)

DEFAULT_TIMESTAMP = 1640991600
ESCAPE_SECURITY_PERIOD = 24*7*60*60

VERSION = str_to_felt('0.2.2')

IACCOUNT_ID = 0xf10dbd44


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet

def update_starknet_block(starknet, block_number=1, block_timestamp=DEFAULT_TIMESTAMP):
    starknet.state.state.block_info = BlockInfo(
        block_number=block_number,
        block_timestamp=block_timestamp,
        gas_price=0,
        starknet_version="0.9.1",
        sequencer_address=starknet.state.state.block_info.sequencer_address)

def reset_starknet_block(starknet):
    update_starknet_block(starknet=starknet)

@pytest.fixture
async def account_factory(get_starknet):
    starknet = get_starknet
    account = await deploy(starknet, "contracts/ArgentAccount.cairo")
    await account.initialize(signer.public_key, 0).invoke()
    return account

@pytest.fixture
async def dapp_factory(get_starknet):
    starknet = get_starknet
    dapp = await deploy(starknet, "contracts/test/TestDapp.cairo")
    dapp2 = await deploy(starknet, "contracts/test/TestDapp.cairo")
    return dapp, dapp2

@pytest.fixture
async def plugin_factory(get_starknet):
    starknet = get_starknet
    plugin_session = await declare(starknet, "contracts/plugins/SessionKey.cairo")
    return plugin_session.class_hash

@pytest.mark.asyncio
async def test_add_plugin(account_factory, plugin_factory):
    account = account_factory
    plugin = plugin_factory
    sender = TransactionSender(account)

    assert (await account.is_plugin(plugin).call()).result.success == (0)
    await sender.send_transaction([(account.contract_address, 'add_plugin', [plugin])], [signer])
    assert (await account.is_plugin(plugin).call()).result.success == (1)

@pytest.mark.asyncio
async def test_remove_plugin(account_factory, plugin_factory):
    account = account_factory
    plugin = plugin_factory
    sender = TransactionSender(account)

    assert (await account.is_plugin(plugin).call()).result.success == (0)
    await sender.send_transaction([(account.contract_address, 'add_plugin', [plugin])], [signer])
    assert (await account.is_plugin(plugin).call()).result.success == (1)
    await sender.send_transaction([(account.contract_address, 'remove_plugin', [plugin])], [signer])
    assert (await account.is_plugin(plugin).call()).result.success == (0)

@pytest.mark.asyncio
async def test_call_dapp_with_session_key(account_factory, plugin_factory, dapp_factory, get_starknet):
    account = account_factory
    plugin = plugin_factory
    dapp, dapp2 = dapp_factory
    starknet = get_starknet
    sender = TransactionSender(account)

    # add session key plugin
    await sender.send_transaction([(account.contract_address, 'add_plugin', [plugin])], [signer])
    # authorise session key
    merkle_leaves = get_leaves(
        [dapp.contract_address, dapp.contract_address, dapp2.contract_address, dapp2.contract_address, dapp2.contract_address],
        [get_selector_from_name('set_number'), get_selector_from_name('set_number_double'), get_selector_from_name('set_number'), get_selector_from_name('set_number_double'), get_selector_from_name('set_number_times3')]
    )    
    leaves = list(map(lambda x: x[0], merkle_leaves))
    root = generate_merkle_root(leaves)
    session_token = get_session_token(session_key.public_key, DEFAULT_TIMESTAMP + 10, root)

    proof = generate_merkle_proof(leaves, 0)
    proof2 = generate_merkle_proof(leaves, 4)
    
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    update_starknet_block(starknet=starknet, block_timestamp=(DEFAULT_TIMESTAMP))
    # call with session key
    # passing once the len(proof). if odd nb of leaves proof will be filled with 0.
    tx_exec_info = await sender.send_transaction(
        [
            (account.contract_address, 'use_plugin', [plugin, session_key.public_key, DEFAULT_TIMESTAMP + 10, session_token[0], session_token[1], root, len(proof), *proof, *proof2]),
            (dapp.contract_address, 'set_number', [47]),
            (dapp2.contract_address, 'set_number_times3', [20])
        ], 
        [session_key])

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='transaction_executed'
    )
    # check it worked
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47
    assert (await dapp2.get_number(account.contract_address).call()).result.number == 60

    # wrong policy call with random proof
    await assert_revert(
        sender.send_transaction(
            [
                (account.contract_address, 'use_plugin', [plugin, session_key.public_key, DEFAULT_TIMESTAMP + 10, session_token[0], session_token[1], root, len(proof), *proof]),
                (dapp.contract_address, 'set_number_times3', [47])
            ], 
            [session_key]),
        "Not allowed by policy"
    )

    # revoke session key
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'execute_on_plugin', [plugin, get_selector_from_name('revoke_session_key'), 1, session_key.public_key])], [signer])
    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='session_key_revoked'
    )
    # check the session key is no longer authorised
    await assert_revert(
        sender.send_transaction(
            [
                (account.contract_address, 'use_plugin', [plugin, session_key.public_key, DEFAULT_TIMESTAMP + 10, session_token[0], session_token[1], root, len(proof), *proof]),
                (dapp.contract_address, 'set_number', [47])
            ], 
            [session_key]),
        "session key revoked"
    )

def get_session_token(key, expires, root):
    session = [
        key,
        expires,
        root
    ]
    hash = compute_hash_on_elements(session)
    return signer.sign(hash)