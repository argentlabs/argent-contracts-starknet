import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starkware_utils.error_handling import StarkException
from utils.Signer import Signer
from utils.utilities import compile, cached_contract, assert_event_emmited, get_execute_data
from utils.TransactionSender import TransactionSender, from_call_to_call_array
from typing import Optional, List, Tuple

from starkware.starknet.compiler.compile import get_selector_from_name

signer = Signer(1)
guardian = Signer(2)
wrong_signer = Signer(3)
wrong_guardian = Signer(4)


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module', params=[
    "ArgentAccount",
    "ArgentPluginAccount",
])
def account_class(request):
    return compile(f"contracts/account/{request.param}.cairo")

@pytest.fixture(scope='module')
def contract_classes(account_class):
    proxy_cls = compile("contracts/upgrade/Proxy.cairo")
    dapp_cls = compile("contracts/test/TestDapp.cairo")
    return proxy_cls, account_class, dapp_cls

@pytest.fixture(scope='module')
async def contract_init(contract_classes):
    proxy_cls, account_cls, dapp_cls = contract_classes
    starknet = await Starknet.empty()

    account_decl = await starknet.declare(contract_class=account_cls)
    account_2_decl = await starknet.declare(contract_class=account_cls)
    non_account_decl = await starknet.declare(contract_class=dapp_cls)

    proxy = await starknet.deploy(
        contract_class=proxy_cls,
        constructor_calldata=[account_decl.class_hash, get_selector_from_name('initialize'), 2, signer.public_key, guardian.public_key]
    )

    wrong_proxy = await starknet.deploy(
        contract_class=proxy_cls,
        constructor_calldata=[account_decl.class_hash, get_selector_from_name('initialize'), 2, wrong_signer.public_key, wrong_guardian.public_key]
    )

    dapp = await starknet.deploy(
        contract_class=dapp_cls,
        constructor_calldata=[],
    )

    return starknet.state, proxy, wrong_proxy, dapp, account_decl.class_hash, account_2_decl.class_hash, non_account_decl.class_hash


@pytest.fixture
def contract_factory(contract_classes, contract_init):
    proxy_cls, implementation_cls, dapp_cls = contract_classes
    state, proxy, wrong_proxy, dapp, account_class, account_2_class, non_acccount_class = contract_init
    _state = state.copy()

    proxy = cached_contract(_state, proxy_cls, proxy)
    account = cached_contract(_state, implementation_cls, proxy)
    wrong_account = cached_contract(_state, implementation_cls, wrong_proxy)
    dapp = cached_contract(_state, dapp_cls, dapp)

    return proxy, account, wrong_account, dapp, account_class, account_2_class, non_acccount_class


@pytest.mark.asyncio
async def test_initializer(contract_factory):
    proxy, account, wrong_account, _, account_class, _, _ = contract_factory

    assert (await proxy.get_implementation().call()).result.implementation == account_class
    assert (await account.getSigner().call()).result.signer == signer.public_key
    assert (await account.getGuardian().call()).result.guardian == guardian.public_key
    assert (await wrong_account.getSigner().call()).result.signer == wrong_signer.public_key
    assert (await wrong_account.getGuardian().call()).result.guardian == wrong_guardian.public_key


@pytest.mark.asyncio
async def test_call_dapp(contract_factory):
    _, account, _, dapp, _, _, _ = contract_factory
    sender = TransactionSender(account)

    # should revert with the wrong signer
    with pytest.raises(StarkException, match="argent: signer signature invalid"):
        await sender.send_transaction([(dapp.contract_address, 'set_number', [47])], [wrong_signer, guardian]),

    # should call the dapp
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction([(dapp.contract_address, 'set_number', [47])], [signer, guardian])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47


def build_execute_after_upgrade_data(calls: Optional[List[Tuple]] = None) -> List[Tuple]:
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
        calls: Optional[List[Tuple]] = None,
) -> Tuple:
    execute_calldata = build_execute_after_upgrade_data(calls)

    upgrade_calldata = [
        new_implementation,
        len(execute_calldata),
        *execute_calldata
    ]

    return account.contract_address, 'upgrade', upgrade_calldata


@pytest.mark.asyncio
async def test_upgrade(contract_factory):
    proxy, account, _, dapp, account_class, account_2_class, non_account_class = contract_factory
    sender = TransactionSender(account)

    # should revert with the wrong guardian
    with pytest.raises(StarkException, match="argent: guardian signature invalid"):
        await sender.send_transaction(
                [build_upgrade_call(account, account_2_class)],
                [signer, wrong_guardian]
            )

    # should revert when the target is not an account
    with pytest.raises(StarkException, match="argent: invalid implementation") as exc_info:
        await sender.send_transaction(
            [build_upgrade_call(account, non_account_class)],
            [signer, guardian]
        ),
    assert exc_info.value.code == StarknetErrorCode.ENTRY_POINT_NOT_FOUND_IN_CONTRACT

    assert (await proxy.get_implementation().call()).result.implementation == account_class

    tx_exec_info = await sender.send_transaction(
        [build_upgrade_call(account, account_2_class)],
        [signer, guardian]
    )

    ret_execute = get_execute_data(tx_exec_info)
    assert len(ret_execute) == 1, "Unexpected return data length"
    assert ret_execute[0] == 0, "Expected 0 calls to be executed after upgrade"

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='account_upgraded',
        data=[account_2_class]
    )

    assert (await proxy.get_implementation().call()).result.implementation == account_2_class


@pytest.mark.asyncio
async def test_upgrade_exec(contract_factory):
    proxy, account, _, dapp, account_class, account_2_class, non_account_class = contract_factory
    sender = TransactionSender(account)

    assert (await proxy.get_implementation().call()).result.implementation == account_class
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0

    increase_number_call = (dapp.contract_address, 'increase_number', [47])

    tx_exec_info = await sender.send_transaction(
        [build_upgrade_call(account, account_2_class, [increase_number_call])],
        [signer, guardian]
    )

    ret_execute = get_execute_data(tx_exec_info)
    assert len(ret_execute) == 2, "Unexpected return data length"
    assert ret_execute[0] == 1, "Expected 1 call to be executed after upgrade"
    assert ret_execute[1] == 47, "Expected new_number returned"

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='account_upgraded',
        data=[account_2_class]
    )

    assert (await proxy.get_implementation().call()).result.implementation == account_2_class
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47


async def test_upgrade_many_calls(contract_factory):
    proxy, account, _, dapp, account_class, account_2_class, non_account_class = contract_factory
    sender = TransactionSender(account)

    assert (await proxy.get_implementation().call()).result.implementation == account_class
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0

    increase_number_call = (dapp.contract_address, 'increase_number', [47])
    increase_number_again_call = (dapp.contract_address, 'increase_number', [1])

    tx_exec_info = await sender.send_transaction(
        [build_upgrade_call(account, account_2_class, [increase_number_call, increase_number_again_call])],
        [signer, guardian]
    )

    ret_execute = get_execute_data(tx_exec_info)
    assert len(ret_execute) == 3, "Unexpected return data length"
    assert ret_execute[0] == 2, "Expected 2 calls to be executed after upgrade"
    assert ret_execute[1] == 47, "Expected new_number returned from first call"
    assert ret_execute[2] == 48, "Expected new_number returned form second call"

    assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='account_upgraded',
        data=[account_2_class]
    )

    assert (await proxy.get_implementation().call()).result.implementation == account_2_class
    assert (await dapp.get_number(account.contract_address).call()).result.number == 48


async def test_execute_after_upgrade_safety(contract_factory):
    proxy, account, wrong_account, dapp, account_class, account_2_class, non_account_class = contract_factory
    sender = TransactionSender(account)
    wrong_sender = TransactionSender(wrong_account)
    set_number_call = (dapp.contract_address, 'set_number', [47])
    assert (await proxy.get_implementation().call()).result.implementation == account_class
    execute_after_upgrade_call = (
        account.contract_address,
        "execute_after_upgrade",
        build_execute_after_upgrade_data([set_number_call])
    )

    # Can't call execute_after_upgrade directly (single call)
    with pytest.raises(StarkException, match="argent: forbidden call"):
        await sender.send_transaction(
            [execute_after_upgrade_call],
            [signer, guardian]
        )

    # Can't call execute_after_upgrade directly (multicall call)
    with pytest.raises(StarkException):
        await sender.send_transaction(
            [set_number_call, execute_after_upgrade_call],
            [signer, guardian]
        )

    # Can't call execute_after_upgrade externally
    with pytest.raises(StarkException, match="argent: only self"):
        await wrong_sender.send_transaction(
            [execute_after_upgrade_call],
            [wrong_signer, wrong_guardian]
        )

    # execute_after_upgrade can't call the wallet
    change_signer_call = (
        account.contract_address,
        "changeSigner",
        [wrong_signer.public_key]
    )
    with pytest.raises(StarkException, match="argent: multicall 0 failed"):
        await sender.send_transaction(
            [build_upgrade_call(account, account_2_class, [change_signer_call])],
            [signer, guardian]
        )
