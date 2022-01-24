import pytest
import asyncio
import logging

from starkware.starknet.testing.starknet import Starknet
from starkware.cairo.common.hash_state import compute_hash_on_elements

from utils.deploy import deploy

LOGGER = logging.getLogger(__name__)

PREFIX_TRANSACTION = 0x537461726b4e6574205472616e73616374696f6e # 'StarkNet Transaction'

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet

@pytest.fixture
async def contract_factory(get_starknet):
    starknet = get_starknet
    contract = await deploy(starknet, "contracts/test/GetExecuteHash.cairo")
    return contract

def hash_multicall(account, calls, nonce):
    hash_array = []
    for call in calls:
        call_elements = [call[0], call[1], compute_hash_on_elements(call[2])]
        hash_array.append(compute_hash_on_elements(call_elements))

    message = [
        PREFIX_TRANSACTION,
        account,
        compute_hash_on_elements(hash_array),
        nonce
    ]
    return compute_hash_on_elements(message)

@pytest.mark.asyncio
async def test_call_1(contract_factory):
    contract = contract_factory
    to = 0x69221ff9023c4d7ba9123f0f9c32634c23fc5776d86657f464ecb51fd811445
    selector = 0xdec8c0606b11c86d32035a34cac464fce6da3af5160a7a9a1a0b383db8de83
    calldata = [1, 3, 7]
    nonce = 7

    call_1 = (to, selector, calldata)
    hash = hash_multicall(contract.contract_address, [call_1], nonce)
    assert (await contract.test_get_execute_hash_1(to, selector, calldata, nonce).call()).result.res == (hash)

@pytest.mark.asyncio
async def test_call_2(contract_factory):
    contract = contract_factory
    to_1 = 0x69221ff9023c4d7ba9123f0f9c32634c23fc5776d86657f464ecb51fd811445
    selector_1 = 0xdec8c0606b11c86d32035a34cac464fce6da3af5160a7a9a1a0b383db8de83
    calldata_1 = [1, 3, 7]
    to_2 = 0x11111ff9023c4d7ba9123f0f9c32634c23fc5776d86657f464ecb51fd811433
    selector_2 = 0x309e00d93c6f8c0c2fcc1c8a01976f72e03b95841c3e3a1f7614048d5a77ead
    calldata_2 = [66, 78, 0, 0, 3]
    nonce = 7

    call_1 = (to_1, selector_1, calldata_1)
    call_2 = (to_2, selector_2, calldata_2)
    hash = hash_multicall(contract.contract_address, [call_1, call_2], nonce)
    assert (await contract.test_get_execute_hash_2(
            to_1, selector_1, calldata_1,
            to_2, selector_2, calldata_2,
            nonce
        ).call()).result.res == (hash)