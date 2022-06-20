import pytest
import asyncio
import logging
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.business_logic.state.state import BlockInfo
from utils.Signer import Signer
from utils.utilities import deploy, declare, assert_revert, str_to_felt, assert_event_emmited
from utils.TransactionSender import TransactionSender

signer = Signer(123456789987654321)

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet

@pytest.fixture
async def account_factory(get_starknet):
    starknet = get_starknet
    account = await deploy(starknet, "contracts/ArgentAccount.cairo")
    await account.initialize(signer.public_key, 0).invoke()
    return account

@pytest.mark.asyncio
async def test_deploy_contract(get_starknet, account_factory):
    starknet = get_starknet
    account = account_factory
    sender = TransactionSender(account)

    class_hash = (await declare(starknet, "contracts/test/TestDapp.cairo")).class_hash

    # deploy dapp contract
    constructor_args = []
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'deploy_contract', [class_hash, 0, constructor_args])], [signer])

    event = assert_event_emmited(
        tx_exec_info,
        from_address=account.contract_address,
        name='contract_deployed'
    )

    logging.INFO(event)
