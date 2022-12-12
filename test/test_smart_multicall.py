import pytest

from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from utils.Signer import Signer
from utils.utilities import cached_contract, compile, assert_revert, str_to_felt, assert_event_emitted, update_starknet_block, reset_starknet_block, DEFAULT_TIMESTAMP
from utils.TransactionSender import TransactionSender

signer = Signer(1)
guardian = Signer(2)

TYPE_VALUE = 0
TYPE_REF = 1

@pytest.fixture(scope='module')
async def contract_init(starknet: Starknet, account_cls: ContractClass, test_dapp_cls: ContractClass):
    account = await starknet.deploy(
        contract_class=account_cls,
        constructor_calldata=[]
    )
    await account.initialize(signer.public_key, guardian.public_key).execute()

    account_no_guardian = await starknet.deploy(
        contract_class=account_cls,
        constructor_calldata=[]
    )
    await account_no_guardian.initialize(signer.public_key, 0).execute()

    dapp = await starknet.deploy(
        contract_class=test_dapp_cls,
        constructor_calldata=[],
    )

    return starknet.state, account, account_no_guardian, dapp


@pytest.fixture
async def contract_factory(account_cls: ContractClass, test_dapp_cls: ContractClass, contract_init):
    state, account, account_no_guardian, dapp = contract_init
    _state = state.copy()

    account = cached_contract(_state, account_cls, account)
    account_no_guardian = cached_contract(_state, account_cls, account_no_guardian)
    dapp = cached_contract(_state, test_dapp_cls, dapp)

    return account, account_no_guardian, dapp

async def test_assert(contract_factory):
    _, account, dapp = contract_factory
    sender = TransactionSender(account)

    call_array = [
        (0, 'use_smart_multicall', 0, 0),
        (dapp.contract_address, 'set_number', 0, 1),
        (dapp.contract_address, 'get_number', 2, 1),
        (dapp.contract_address, 'check_le', 4, 2),
    ]

    calldata_fails = [
        TYPE_VALUE, 47,
        TYPE_VALUE, account.contract_address,
        TYPE_REF, 0, TYPE_VALUE, 30,
    ]

    calldata_success = [
        TYPE_VALUE, 47,
        TYPE_VALUE, account.contract_address,
        TYPE_REF, 0, TYPE_VALUE, 50,
    ]

    # should revert
    await assert_revert(
        sender.send_call_array_transaction(call_array, calldata_fails, [signer]),
        "check le failed"
    )

    # should succeed
    tx_exec_info = await sender.send_call_array_transaction(call_array, calldata_success, [signer])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='transaction_executed'
    )

async def test_add(contract_factory):
    _, account, dapp = contract_factory
    sender = TransactionSender(account)

    call_array = [
        (0, 'use_smart_multicall', 0, 0),
        (dapp.contract_address, 'set_number', 0, 1),
        (dapp.contract_address, 'get_number', 2, 1),
        (dapp.contract_address, 'add', 4, 2),
        (dapp.contract_address, 'check_le', 8, 2),
    ]

    calldata_fails = [
        TYPE_VALUE, 5,
        TYPE_VALUE, account.contract_address,
        TYPE_REF, 0, TYPE_VALUE, 10,
        TYPE_REF, 1, TYPE_VALUE, 14,
    ]

    calldata_success = [
        TYPE_VALUE, 5,
        TYPE_VALUE, account.contract_address,
        TYPE_REF, 0, TYPE_VALUE, 10,
        TYPE_REF, 1, TYPE_VALUE, 16,
    ]

    # should revert
    await assert_revert(
        sender.send_call_array_transaction(call_array, calldata_fails, [signer]),
        "check le failed"
    )

    # should succeed
    tx_exec_info = await sender.send_call_array_transaction(call_array, calldata_success, [signer])

    assert_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='transaction_executed'
    )