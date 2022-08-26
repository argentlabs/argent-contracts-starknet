import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.definitions.general_config import StarknetChainId
from utils.Signer import Signer
from utils.utilities import cached_contract, compile, str_to_felt, assert_revert, assert_event_emmited, DEFAULT_TIMESTAMP, update_starknet_block
from utils.TransactionSender import TransactionSender
from starkware.cairo.common.hash_state import compute_hash_on_elements
from starkware.starknet.compiler.compile import get_selector_from_name
from utils.merkle_utils import generate_merkle_proof, generate_merkle_root, get_leaves, verify_merkle_proof

signer = Signer(1)
session_key = Signer(2)
wrong_session_key = Signer(3)

# H('StarkNetDomain(chainId:felt)')
STARKNET_DOMAIN_TYPE_HASH = 0x13cda234a04d66db62c06b8e3ad5f91bd0c67286c2c7519a826cf49da6ba478
# H('Session(key:felt,expires:felt,root:merkletree)')
SESSION_TYPE_HASH = 0x1aa0e1c56b45cf06a54534fa1707c54e520b842feb21d03b7deddb6f1e340c
# H(Policy(contractAddress:felt,selector:selector))
POLICY_TYPE_HASH = 0x2f0026e78543f036f33e26a8f5891b88c58dc1e20cbbfaf0bb53274da6fa568

def get_session_token(session_key, session_expires, root, chain_id, account):

    domain_hash = compute_hash_on_elements([STARKNET_DOMAIN_TYPE_HASH, chain_id])
    message_hash = compute_hash_on_elements([SESSION_TYPE_HASH, session_key, session_expires, root])
    
    hash = compute_hash_on_elements([
        str_to_felt('StarkNet Message'),
        domain_hash,
        account,
        message_hash
    ])
    return signer.sign(hash)

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
def contract_classes():
    account_cls = compile('contracts/ArgentPluginAccount.cairo')
    dapp_cls = compile("contracts/test/TestDapp.cairo")
    session_plugin_cls = compile("contracts/plugins/SessionKey.cairo")
    
    return account_cls, dapp_cls, session_plugin_cls

@pytest.fixture(scope='module')
async def contract_init(contract_classes):
    account_cls, dapp_cls, session_plugin_cls = contract_classes
    starknet = await Starknet.empty()

    account = await starknet.deploy(
        contract_class=account_cls,
        constructor_calldata=[]
    )
    await account.initialize(signer.public_key, 0).invoke()

    dapp = await starknet.deploy(
        contract_class=dapp_cls,
        constructor_calldata=[]
    )

    dapp2 = await starknet.deploy(
        contract_class=dapp_cls,
        constructor_calldata=[]
    )

    session_plugin_decl = await starknet.declare(contract_class=session_plugin_cls)

    return starknet.state, account, dapp, dapp2, session_plugin_decl.class_hash

@pytest.fixture
def contract_factory(contract_classes, contract_init):
    account_cls, dapp_cls, session_plugin_cls = contract_classes
    state, account, dapp, dapp2, session_plugin_class = contract_init
    _state = state.copy()

    account = cached_contract(_state, account_cls, account)
    dapp = cached_contract(_state, dapp_cls, dapp)
    dapp2 = cached_contract(_state, dapp_cls, dapp2)

    return account, dapp, dapp2, session_plugin_class

@pytest.mark.asyncio
async def test_add_plugin(contract_factory):
    account, _, _, session_plugin = contract_factory
    sender = TransactionSender(account)

    assert (await account.is_plugin(session_plugin).call()).result.success == (0)
    await sender.send_transaction([(account.contract_address, 'add_plugin', [session_plugin])], [signer])
    assert (await account.is_plugin(session_plugin).call()).result.success == (1)

@pytest.mark.asyncio
async def test_remove_plugin(contract_factory):
    account, _, _, session_plugin = contract_factory
    sender = TransactionSender(account)

    assert (await account.is_plugin(session_plugin).call()).result.success == (0)
    await sender.send_transaction([(account.contract_address, 'add_plugin', [session_plugin])], [signer])
    assert (await account.is_plugin(session_plugin).call()).result.success == (1)
    await sender.send_transaction([(account.contract_address, 'remove_plugin', [session_plugin])], [signer])
    assert (await account.is_plugin(session_plugin).call()).result.success == (0)

@pytest.mark.asyncio
async def test_call_dapp_with_session_key(contract_factory):
    account, dapp, dapp2, session_plugin = contract_factory
    sender = TransactionSender(account)

    # add session key plugin
    await sender.send_transaction([(account.contract_address, 'add_plugin', [session_plugin])], [signer])
    # authorise session key
    merkle_leaves = get_leaves(
        POLICY_TYPE_HASH,
        [dapp.contract_address, dapp.contract_address, dapp2.contract_address, dapp2.contract_address, dapp2.contract_address],
        [get_selector_from_name('set_number'), get_selector_from_name('set_number_double'), get_selector_from_name('set_number'), get_selector_from_name('set_number_double'), get_selector_from_name('set_number_times3')]
    )    
    leaves = list(map(lambda x: x[0], merkle_leaves))
    root = generate_merkle_root(leaves)
    session_token = get_session_token(session_key.public_key, DEFAULT_TIMESTAMP + 10, root, StarknetChainId.TESTNET.value, account.contract_address)

    proof = generate_merkle_proof(leaves, 0)
    proof2 = generate_merkle_proof(leaves, 4)
    
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    update_starknet_block(state=account.state, block_timestamp=(DEFAULT_TIMESTAMP))
    # call with session key
    # passing once the len(proof). if odd nb of leaves proof will be filled with 0.
    tx_exec_info = await sender.send_transaction(
        [
            (account.contract_address, 'use_plugin', [session_plugin, session_key.public_key, DEFAULT_TIMESTAMP + 10, root, len(proof), *proof, *proof2, *session_token]),
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
                (account.contract_address, 'use_plugin', [session_plugin, session_key.public_key, DEFAULT_TIMESTAMP + 10, root, len(proof), *proof, *session_token]),
                (dapp.contract_address, 'set_number_times3', [47])
            ], 
            [session_key]),
        "not allowed by policy"
    )

    # revoke session key
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'execute_on_plugin', [session_plugin, get_selector_from_name('revoke_session_key'), 1, session_key.public_key])], [signer])
    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='session_key_revoked'
    )
    # check the session key is no longer authorised
    await assert_revert(
        sender.send_transaction(
            [
                (account.contract_address, 'use_plugin', [session_plugin, session_key.public_key, DEFAULT_TIMESTAMP + 10, root, len(proof), *proof, *session_token]),
                (dapp.contract_address, 'set_number', [47])
            ], 
            [session_key]),
        "session key revoked"
    )