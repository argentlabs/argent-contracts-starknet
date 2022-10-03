import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from utils.Signer import Signer
from utils.utilities import cached_contract, compile, find_event_emited, str_to_felt
from starkware.starknet.core.os.class_hash import compute_class_hash
from starkware.cairo.lang.vm.crypto import pedersen_hash
from utils.TransactionSender import TransactionSender
from starkware.starknet.compiler.compile import get_selector_from_name
from starkware.cairo.common.hash_state import compute_hash_on_elements


signer = Signer(1)
guardian = Signer(2)

CONTRACT_ADDRESS_PREFIX = str_to_felt('STARKNET_CONTRACT_ADDRESS')
UNIVERSAL_DEPLOYER_PREFIX = str_to_felt('UniversalDeployerContract')

def compute_address(caller_address, salt, class_hash, constructor_calldata):

    _salt = pedersen_hash(UNIVERSAL_DEPLOYER_PREFIX, salt)
    constructor_calldata_hash = compute_hash_on_elements(constructor_calldata)

    return compute_hash_on_elements(
        [
            CONTRACT_ADDRESS_PREFIX,
            caller_address,
            _salt,
            class_hash,
            constructor_calldata_hash,
        ])


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
def contract_classes():
    proxy_cls = compile("contracts/upgrade/Proxy.cairo")
    account_cls = compile('contracts/account/ArgentAccount.cairo')
    deployer_cls = compile('contracts/lib/UniversalDeployer.cairo')
    
    return proxy_cls, account_cls, deployer_cls

@pytest.fixture(scope='module')
async def contract_init(contract_classes):
    proxy_cls, account_cls, deployer_cls = contract_classes
    starknet = await Starknet.empty()

    proxy_decl = await starknet.declare(contract_class=proxy_cls)
    account_decl = await starknet.declare(contract_class=account_cls)
    deployer_decl = await starknet.declare(contract_class=deployer_cls)

    account = await starknet.deploy(
        contract_class=account_cls,
        constructor_calldata=[]
    )
    await account.initialize(signer.public_key, 0).execute()

    deployer = await starknet.deploy(
        contract_class=deployer_cls,
        constructor_calldata=[]
    )

    return proxy_decl.class_hash, account_decl.class_hash, account, deployer

@pytest.mark.asyncio
async def test_deployer(contract_init):
    proxy_hash, account_hash, account, deployer = contract_init
    sender = TransactionSender(account)

    salt = str_to_felt('salt')
    constructor_calldata = [account_hash, get_selector_from_name('initialize'), 2, signer.public_key, guardian.public_key]

    # get the counter factual address
    counterfactual_address = compute_address(0, salt, proxy_hash, constructor_calldata)
    # deploy with deployer
    tx_exec_info = await sender.send_transaction([(deployer.contract_address, 'deployContract', [proxy_hash, salt, 0, 5, account_hash, get_selector_from_name('initialize'), 2, signer.public_key, guardian.public_key])], [signer])
    # check that adddress is the same
    event = find_event_emited(tx_exec_info, deployer.contract_address, 'ContractDeployed')
    assert event.data[0] == counterfactual_address



