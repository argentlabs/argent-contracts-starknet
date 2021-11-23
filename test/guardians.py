import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starknet.testing.objects import StarknetContractCall
from starkware.starknet.public.abi import get_selector_from_name
from utils.Signer import Signer
from utils.deploy import deploy
from utils.TransactionBuilder import TransactionBuilder

account_signer = Signer(123456789987654321)
guardian_1_key = Signer(1111111111111)
guardian_2_key_1 = Signer(2222222222222)
guardian_2_key_2 = Signer(3333333333333)

L1_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984
ESCAPE_SECURITY_PERIOD = 500

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet

@pytest.fixture
async def account_factory(get_starknet):
    async def _account_factory(guardian):
        starknet = get_starknet
        account = await deploy(starknet, "contracts/ArgentAccount.cairo", [account_signer.public_key, guardian, L1_ADDRESS])
        return account
    return _account_factory

@pytest.fixture
async def guardian_factory(get_starknet):
    starknet = get_starknet
    guardian1 = await deploy(starknet, "contracts/guardians/SCSKGuardian.cairo", [guardian_1_key.public_key])
    guardian2 = await deploy(starknet, "contracts/guardians/USDKGuardian.cairo")
    return guardian1, guardian2

@pytest.fixture
async def dapp_factory(get_starknet):
    starknet = get_starknet
    dapp = await deploy(starknet, "contracts/TestDapp.cairo")
    return dapp

@pytest.mark.asyncio
async def test_guardian_suite(account_factory, guardian_factory, dapp_factory):
    guardian1, guardian2 = guardian_factory
    account = await account_factory(guardian1.contract_address)
    dapp = dapp_factory
    builder = TransactionBuilder(account, account_signer, guardian_1_key)
    nonce = await builder.get_nonce()
    # check the guardian at start
    assert (await account.get_guardian().call()).result.guardian == (guardian1.contract_address)
    # configure the second guardian
    (transaction, signatures) = builder.build_execute_transaction(guardian2.contract_address, 'set_signing_key', [guardian_2_key_1.public_key], nonce)
    await transaction.invoke(signature=signatures)
    (transaction, signatures) = builder.build_execute_transaction(guardian2.contract_address, 'set_escape_key', [guardian_2_key_2.public_key], nonce + 1)
    await transaction.invoke(signature=signatures)
    # check that the configuration worked
    assert (await guardian2.get_signing_key(account.contract_address).call()).result.signing_key == guardian_2_key_1.public_key
    assert (await guardian2.get_escape_key(account.contract_address).call()).result.escape_key == guardian_2_key_2.public_key
    # change guardian
    (transaction, signatures) = builder.build_change_guardian_transaction(guardian2.contract_address, nonce + 2)
    await transaction.invoke(signature=signatures)
    # check that the change worked
    assert (await account.get_guardian().call()).result.guardian == (guardian2.contract_address)
    # check that the USKD guardian can sign regular calls with the signing key
    builder = TransactionBuilder(account, account_signer, guardian_2_key_1)
    (transaction, signatures) = builder.build_execute_transaction(dapp.contract_address, 'set_number', [47], nonce + 3)
    await transaction.invoke(signature=signatures)
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47
    # check that the USKD guardian cannot sign escape with the signing key
    try:
        (transaction, signatures) = builder.build_trigger_escape_transaction(guardian2.contract_address, guardian_2_key_1, nonce + 4)
        await transaction.invoke(signature=signatures)
        assert False
    except StarkException as err:
        _, error = err.args
        assert error['code'] == StarknetErrorCode.TRANSACTION_FAILED
    # check that the USKD guardian can sign escape with the escape key
    builder = TransactionBuilder(account, account_signer, guardian_2_key_2)
    await builder.set_block_timestamp(127)
    (transaction, signatures) = builder.build_trigger_escape_transaction(guardian2.contract_address, guardian_2_key_2, nonce + 4)
    await transaction.invoke(signature=signatures)
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == guardian2.contract_address)
