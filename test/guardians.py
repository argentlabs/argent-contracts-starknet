import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starknet.testing.objects import StarknetContractCall
from starkware.crypto.signature.signature import pedersen_hash
from utils.Signer import Signer
from utils.deploy import deploy
from utils.TransactionSender import TransactionSender

account_signer = Signer(123456789987654321)
guardian_1_key = Signer(1111111111111)
guardian_2_key_1 = Signer(2222222222222)
guardian_2_key_2 = Signer(3333333333333)

ESCAPE_SECURITY_PERIOD = 500

async def assert_revert(expression):
    try:
        await expression
        assert False
    except StarkException as err:
        _, error = err.args
        assert error['code'] == StarknetErrorCode.TRANSACTION_FAILED

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
        account = await deploy(starknet, "contracts/ArgentAccount.cairo", [account_signer.public_key, guardian])
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
async def test_scsk_guardian(account_factory, guardian_factory, dapp_factory):
    guardian1, _ = guardian_factory
    account = await account_factory(guardian1.contract_address)
    dapp = dapp_factory
    sender = TransactionSender(account)

    # is configured correctly
    assert (await guardian1.get_signing_key().call()).result.signing_key == (guardian_1_key.public_key)

    # can approve transactions
    assert (await dapp.get_number(account.contract_address).call()).result.number == 0
    await sender.send_transaction(dapp.contract_address, 'set_number', [47], [account_signer, guardian_1_key])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47

    # can set a new key
    guardian_1_key_new = Signer(455667754)
    hash = pedersen_hash(guardian_1_key_new.public_key, 0)
    signature = list(guardian_1_key.sign(hash))
    await guardian1.set_signing_key(guardian_1_key_new.public_key).invoke(signature=signature)
    assert (await guardian1.get_signing_key().call()).result.signing_key == (guardian_1_key_new.public_key)

    # new key can approve transactions
    await sender.send_transaction(dapp.contract_address, 'set_number', [57], [account_signer, guardian_1_key_new])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 57

    # old key cannot approve transactions
    await assert_revert(
        sender.send_transaction(dapp.contract_address, 'set_number', [67], [account_signer, guardian_1_key])
    )

@pytest.mark.asyncio
async def test_guardian_suite(account_factory, guardian_factory, dapp_factory):
    guardian1, guardian2 = guardian_factory
    account = await account_factory(guardian1.contract_address)
    dapp = dapp_factory
    sender = TransactionSender(account)
    # check the guardian at start
    assert (await account.get_guardian().call()).result.guardian == (guardian1.contract_address)
    # configure the second guardian
    await sender.send_transaction(guardian2.contract_address, 'set_signing_key', [guardian_2_key_1.public_key], [account_signer, guardian_1_key])
    await sender.send_transaction(guardian2.contract_address, 'set_escape_key', [guardian_2_key_2.public_key], [account_signer, guardian_1_key])
    # check that the configuration worked
    assert (await guardian2.get_signing_key(account.contract_address).call()).result.signing_key == guardian_2_key_1.public_key
    assert (await guardian2.get_escape_key(account.contract_address).call()).result.escape_key == guardian_2_key_2.public_key
    # change guardian
    await sender.send_transaction(account.contract_address, 'change_guardian', [guardian2.contract_address], [account_signer, guardian_1_key])
    # check that the change worked
    assert (await account.get_guardian().call()).result.guardian == (guardian2.contract_address)
    # check that the USKD guardian can sign regular calls with the signing key
    await sender.send_transaction(dapp.contract_address, 'set_number', [47], [account_signer, guardian_2_key_1])
    assert (await dapp.get_number(account.contract_address).call()).result.number == 47
    # check that the USKD guardian cannot sign escape with the signing key
    await sender.set_block_timestamp(127)
    await assert_revert(
        sender.send_transaction(account.contract_address, 'trigger_escape_signer', [], [guardian_2_key_1])
    )
    # check that the USKD guardian can sign escape with the escape key
    await sender.send_transaction(account.contract_address, 'trigger_escape_signer', [], [guardian_2_key_2])
    escape = (await account.get_escape().call()).result
    assert (escape.active_at == (127 + ESCAPE_SECURITY_PERIOD) and escape.caller == guardian2.contract_address)