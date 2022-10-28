import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.definitions.general_config import StarknetChainId
from utils.Signer import Signer
from utils.multisig_utils import MultisigPluginSigner
from utils.utilities import build_contract, compile, str_to_felt, assert_revert, assert_event_emitted, DEFAULT_TIMESTAMP, update_starknet_block
from utils.TransactionSender import TransactionSender
from starkware.cairo.common.hash_state import compute_hash_on_elements
from starkware.starknet.compiler.compile import get_selector_from_name
from utils.merkle_utils import generate_merkle_proof, generate_merkle_root, get_leaves, verify_merkle_proof

signer_key = Signer(1)
wrong_signer_key = Signer(6)


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def starknet():
    return await Starknet.empty()



@pytest.fixture(scope='module')
async def account_setup(starknet: Starknet):
    account_cls = compile('contracts/account/ArgentPluginAccount.cairo')
    multisig_cls = compile('contracts/plugins/MultiSig.cairo')

    account = await starknet.deploy(contract_class=account_cls, constructor_calldata=[])
    multisig_decl = await starknet.declare(contract_class=multisig_cls)

    threshold = 1
    owners = [signer_key.public_key]
    init_params = [
        threshold,
        len(owners),
        *owners
    ]

    await account.initialize(multisig_decl.class_hash, init_params).execute()

    return account, multisig_decl.class_hash


@pytest.fixture(scope='module')
async def dapp(starknet: Starknet):
    dapp_cls = compile('contracts/test/BalanceDapp.cairo')
    await starknet.declare(contract_class=dapp_cls)
    return await starknet.deploy(contract_class=dapp_cls, constructor_calldata=[])


@pytest.fixture
def contracts(starknet: Starknet, account_setup, dapp):
    account, multisig_plugin_address = account_setup
    clean_state = starknet.state.copy()

    account = build_contract(account, state=clean_state)

    multisig_plugin_signer = MultisigPluginSigner(
        keys=[signer_key],
        account=account,
        plugin_address=multisig_plugin_address
    )

    dapp = build_contract(dapp, state=clean_state)

    return multisig_plugin_signer, dapp


@pytest.mark.asyncio
async def test_dapp(contracts):
    multisig_plugin_signer, dapp = contracts
    assert (await dapp.get_balance().call()).result.res == 0
    tx_exec_info = await multisig_plugin_signer.send_transaction(
        calls=[(dapp.contract_address, 'set_balance', [47])],
    )
    assert_event_emitted(
        tx_exec_info,
        from_address=multisig_plugin_signer.account.contract_address,
        name='transaction_executed',
        data=[]
    )
    assert (await dapp.get_balance().call()).result.res == 47