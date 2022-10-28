import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils.Signer import Signer
from utils.multisig_utils import MultisigPluginSigner
from utils.utilities import build_contract, compile, str_to_felt, assert_revert, assert_event_emitted

signer_key = Signer(1)
signer_key_2 = Signer(2)
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


@pytest.mark.asyncio
async def test_1_of_2(contracts):
    multisig_plugin_signer, dapp = contracts
    assert (await dapp.get_balance().call()).result.res == 0

    threshold = 1
    new_owners = [signer_key_2.public_key]
    await multisig_plugin_signer.execute_on_plugin(
        "add_owners",
        [threshold, len(new_owners), *new_owners]
    )

    multisig_plugin_signer_2 = MultisigPluginSigner(
        keys=[signer_key_2],
        account=multisig_plugin_signer.account,
        plugin_address=multisig_plugin_signer.plugin_address
    )

    await multisig_plugin_signer_2.send_transaction(
        calls=[(dapp.contract_address, 'set_balance', [47])],
    )
    assert (await dapp.get_balance().call()).result.res == 47

    await multisig_plugin_signer.send_transaction(
        calls=[(dapp.contract_address, 'set_balance', [48])],
    )
    assert (await dapp.get_balance().call()).result.res == 48

@pytest.mark.asyncio
async def test_2_of_2(contracts):
    multisig_plugin_signer, dapp = contracts
    assert (await dapp.get_balance().call()).result.res == 0

    threshold = 2
    new_owners = [signer_key_2.public_key]
    await multisig_plugin_signer.execute_on_plugin(
        "add_owners",
        [threshold, len(new_owners), *new_owners]
    )

    multisig_plugin_signer_2 = MultisigPluginSigner(
        keys=[signer_key_2],
        account=multisig_plugin_signer.account,
        plugin_address=multisig_plugin_signer.plugin_address
    )

    multisig_plugin_signer_both = MultisigPluginSigner(
        keys=[signer_key, signer_key_2],
        account=multisig_plugin_signer.account,
        plugin_address=multisig_plugin_signer.plugin_address
    )

    multisig_plugin_signer_same_key_twice = MultisigPluginSigner(
        keys=[signer_key, signer_key],
        account=multisig_plugin_signer.account,
        plugin_address=multisig_plugin_signer.plugin_address
    )

    await assert_revert(
        multisig_plugin_signer_2.send_transaction(
            calls=[(dapp.contract_address, 'set_balance', [47])],
        ),
        revert_reason="MultiSig: Not enough (or too many) signatures"
    )

    await assert_revert(
        multisig_plugin_signer.send_transaction(
            calls=[(dapp.contract_address, 'set_balance', [47])],
        ),
        revert_reason="MultiSig: Not enough (or too many) signatures"
    )

    await assert_revert(
        multisig_plugin_signer_same_key_twice.send_transaction(
            calls=[(dapp.contract_address, 'set_balance', [47])],
        ),
        revert_reason="TBD"
    )

    await multisig_plugin_signer_both.send_transaction(
        calls=[(dapp.contract_address, 'set_balance', [47])],
    )
    assert (await dapp.get_balance().call()).result.res == 47

