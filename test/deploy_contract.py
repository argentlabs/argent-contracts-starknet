import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils.Signer import Signer
from utils.utilities import deploy, declare, first_event_emitted
from utils.TransactionSender import TransactionSender
from starkware.starknet.testing.contract import StarknetContract

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
async def test_deploy_contract_no_constructor(get_starknet, account_factory):
    starknet = get_starknet
    account = account_factory
    sender = TransactionSender(account)

    # declare contract class
    declared_class = await declare(starknet, "contracts/test/TestDapp.cairo")

    # deploy contract
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'deploy_contract', [declared_class.class_hash, 0, 0])], [signer])

    event = first_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='contract_deployed'
    )

    deployed_contract = event.data[0]

    # test the deployed contract
    dapp = StarknetContract(state=starknet.state, abi=declared_class.abi, contract_address=deployed_contract, deploy_execution_info=None)

    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    
    tx_exec_info = await sender.send_transaction([(dapp.contract_address, 'set_number', [47])], [signer])

    assert (await dapp.get_number(account.contract_address).call()).result.number == 47

@pytest.mark.asyncio
async def test_deploy_contract_with_constructor(get_starknet, account_factory):
    starknet = get_starknet
    account = account_factory
    sender = TransactionSender(account)

    # declare contract class
    declared_class = await declare(starknet, "contracts/test/TestDapp2.cairo")

    # deploy contract
    tx_exec_info = await sender.send_transaction([(account.contract_address, 'deploy_contract', [declared_class.class_hash, 0, 1, 24])], [signer])

    event = first_event_emitted(
        tx_exec_info,
        from_address=account.contract_address,
        name='contract_deployed'
    )

    deployed_contract = event.data[0]

    # test the deployed contract
    dapp = StarknetContract(state=starknet.state, abi=declared_class.abi, contract_address=deployed_contract, deploy_execution_info=None)

    assert (await dapp.get_number().call()).result.number == 24
    
    tx_exec_info = await sender.send_transaction([(dapp.contract_address, 'set_number', [47])], [signer])

    assert (await dapp.get_number().call()).result.number == 47