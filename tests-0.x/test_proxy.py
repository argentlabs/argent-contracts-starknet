import pytest

from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from utils.Signer import Signer
from utils.utilities import compile, cached_contract, assert_revert, assert_event_emitted, get_execute_data
from utils.TransactionSender import TransactionSender, Call, from_call_to_call_array
from typing import Optional, List, Tuple, Union

from starkware.starknet.compiler.compile import get_selector_from_name

signer = Signer(1)
guardian = Signer(2)
wrong_signer = Signer(3)
wrong_guardian = Signer(4)


@pytest.fixture(scope='module', params=[
    "ArgentAccount",
    "ArgentPluginAccount",
])
def account_class(request, account_cls: ContractClass, plugin_account_cls: ContractClass):
    if request.param == 'ArgentAccount':
        return account_cls
    elif request.param == 'ArgentPluginAccount':
        return plugin_account_cls
    raise Exception(f"Unknown account type {request.param}]")


@pytest.fixture(scope='module')
async def contract_init(starknet: Starknet, proxy_cls: ContractClass, account_class: ContractClass, test_dapp_cls: ContractClass):

    account_decl = await starknet.declare(contract_class=account_class)
    account_2_decl = await starknet.declare(contract_class=account_class)
    non_account_decl = await starknet.declare(contract_class=test_dapp_cls)

    proxy = await starknet.deploy(
        contract_class=proxy_cls,
        constructor_calldata=[account_decl.class_hash, get_selector_from_name('initialize'), 2, signer.public_key, guardian.public_key]
    )

    wrong_proxy = await starknet.deploy(
        contract_class=proxy_cls,
        constructor_calldata=[account_decl.class_hash, get_selector_from_name('initialize'), 2, wrong_signer.public_key, wrong_guardian.public_key]
    )

    dapp = await starknet.deploy(
        contract_class=test_dapp_cls,
        constructor_calldata=[],
    )

    return starknet.state, proxy, wrong_proxy, dapp, account_decl.class_hash, account_2_decl.class_hash, non_account_decl.class_hash


@pytest.fixture
def contract_factory(proxy_cls: ContractClass, account_class: ContractClass, test_dapp_cls: ContractClass, contract_init):
    state, proxy, wrong_proxy, dapp, account_class_hash, account_2_class_hash, non_acccount_class_hash = contract_init
    _state = state.copy()

    proxy = cached_contract(_state, proxy_cls, proxy)
    account = cached_contract(_state, account_class, proxy)
    wrong_account = cached_contract(_state, account_class, wrong_proxy)
    dapp = cached_contract(_state, test_dapp_cls, dapp)

    return proxy, account, wrong_account, dapp, account_class_hash, account_2_class_hash, non_acccount_class_hash


async def test_initializer(contract_factory):
    proxy, account, wrong_account, _, account_class_hash, _, _ = contract_factory

    assert (await proxy.get_implementation().call()).result.implementation == account_class_hash
    assert (await account.getSigner().call()).result.signer == signer.public_key
    assert (await account.getGuardian().call()).result.guardian == guardian.public_key
    assert (await wrong_account.getSigner().call()).result.signer == wrong_signer.public_key
    assert (await wrong_account.getGuardian().call()).result.guardian == wrong_guardian.public_key


async def test_call_dapp(contract_factory):
    _, account, _, dapp, _, _, _ = contract_factory
    sender = TransactionSender(account)

    # should revert with the wrong signer
    await assert_revert(
        sender.send_transaction([(dapp.contract_address, 'set_number', [47])], [wrong_signer, guardian]),
        "argent: signer signature invalid"
    )

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction([(dapp.contract_address, 'set_number', [47])], [signer, guardian])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47


def build_execute_after_upgrade_data(calls: Optional[List[Call]] = None) -> List[Union[int,Tuple]]:
    if calls is None:
        calls = []
    multicall_call_array, multicall_calldata = from_call_to_call_array(calls)
    multicall_call_array_flat = [data for call in multicall_call_array for data in call]

    return [
        len(multicall_call_array),
        *multicall_call_array_flat,
        len(multicall_calldata),
        *multicall_calldata
    ]


def build_upgrade_call(
        account,
        new_implementation,
        calls: Optional[List[Call]] = None,
) -> Call:
    execute_calldata = build_execute_after_upgrade_data(calls)

    upgrade_calldata = [
        new_implementation,
        len(execute_calldata),
        *execute_calldata
    ]

    return account.contract_address, 'upgrade', upgrade_calldata


async def test_upgrade(contract_factory):
    proxy, account, _, dapp, account_class_hash, account_2_class_hash, non_account_class_hash = contract_factory
    sender = TransactionSender(account)

    # should revert with the wrong guardian
    await assert_revert(
        sender.send_transaction(
            [build_upgrade_call(account, account_2_class_hash)],
            [signer, wrong_guardian]
        ),
        "argent: guardian signature invalid"
    )

    # should revert when the target is not an account
    await assert_revert(
        sender.send_transaction(
            [build_upgrade_call(account, non_account_class_hash)],
            [signer, guardian]
        ),
        "argent: invalid implementation",
        StarknetErrorCode.ENTRY_POINT_NOT_FOUND_IN_CONTRACT
    )

    assert (await proxy.get_implementation().call()).result.implementation == account_class_hash

    tx_exec_info = await sender.send_transaction(
        [build_upgrade_call(account, account_2_class_hash)],
        [signer, guardian]
    )

    ret_execute = get_execute_data(tx_exec_info)
    assert len(ret_execute) == 0, "Expected 0 calls to be executed after upgrade"

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='account_upgraded',
        data=[account_2_class_hash]
    )

    assert (await proxy.get_implementation().call()).result.implementation == account_2_class_hash


async def test_upgrade_exec(contract_factory):
    proxy, account, _, dapp, account_class_hash, account_2_class_hash, non_account_class_hash = contract_factory
    sender = TransactionSender(account)

    assert (await proxy.get_implementation().call()).result.implementation == account_class_hash
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0

    increase_number_call: Call = (dapp.contract_address, 'increase_number', [47])

    tx_exec_info = await sender.send_transaction(
        [build_upgrade_call(account, account_2_class_hash, [increase_number_call])],
        [signer, guardian]
    )

    ret_execute = get_execute_data(tx_exec_info)
    assert ret_execute[0] == 1, "Expected call response to be of length 1 "
    assert ret_execute[1] == 47, "Expected new_number returned"

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='account_upgraded',
        data=[account_2_class_hash]
    )

    assert (await proxy.get_implementation().call()).result.implementation == account_2_class_hash
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47


async def test_upgrade_many_calls(contract_factory):
    proxy, account, _, dapp, account_class_hash, account_2_class_hash, non_account_class_hash = contract_factory
    sender = TransactionSender(account)

    assert (await proxy.get_implementation().call()).result.implementation == account_class_hash
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0

    increase_number_call: Call = (dapp.contract_address, 'increase_number', [47])
    increase_number_again_call: Call = (dapp.contract_address, 'increase_number', [1])

    tx_exec_info = await sender.send_transaction(
        [build_upgrade_call(account, account_2_class_hash, [increase_number_call, increase_number_again_call])],
        [signer, guardian]
    )

    ret_execute = get_execute_data(tx_exec_info)
    assert ret_execute[0] == 1, "Expected call 1 response to be of length 1 "
    assert ret_execute[1] == 47, "Expected new_number returned from first call"
    assert ret_execute[2] == 1, "Expected call 2 response to be of length 1 "
    assert ret_execute[3] == 48, "Expected new_number returned form second call"

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='account_upgraded',
        data=[account_2_class_hash]
    )

    assert (await proxy.get_implementation().call()).result.implementation == account_2_class_hash
    assert (await dapp.get_number(account.contract_address).call()).result.number == 48


async def test_execute_after_upgrade_safety(contract_factory):
    proxy, account, wrong_account, dapp, account_class_hash, account_2_class_hash, non_account_class_hash = contract_factory
    sender = TransactionSender(account)
    wrong_sender = TransactionSender(wrong_account)
    set_number_call: Call = (dapp.contract_address, 'set_number', [47])
    assert (await proxy.get_implementation().call()).result.implementation == account_class_hash
    execute_after_upgrade_call: Call = (
        account.contract_address,
        "execute_after_upgrade",
        build_execute_after_upgrade_data([set_number_call])
    )

    # Can't call execute_after_upgrade directly (single call)
    await assert_revert(
        sender.send_transaction(
            [execute_after_upgrade_call],
            [signer, guardian]
        ),
        "argent: forbidden call"
    )

    # Can't call execute_after_upgrade directly (multicall call)
    await assert_revert(
        sender.send_transaction(
            [set_number_call, execute_after_upgrade_call],
            [signer, guardian]
        ),
        # disallowed call to self has no specific message yet
    )

    # Can't call execute_after_upgrade externally
    await assert_revert(
        wrong_sender.send_transaction(
            [execute_after_upgrade_call],
            [wrong_signer, wrong_guardian]
        ),
        "argent: only self"
    )

    # execute_after_upgrade can't call the wallet
    change_signer_call: Call = (
        account.contract_address,
        "changeSigner",
        [wrong_signer.public_key]
    )
    await assert_revert(
        sender.send_transaction(
            [build_upgrade_call(account, account_2_class_hash, [change_signer_call])],
            [signer, guardian]
        ),
        "multicall 1 failed"
    )
