import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.testing.objects import StarknetContractCall
from starkware.starknet.public.abi import get_selector_from_name
from utils.deploy import deploy

user1 = 0x69221ff9023c4d7ba9123f0f9c32634c23fc5776d86657f464ecb51fd811445
user2 = 0x72648c3b1953572d2c4395a610f18b83cca14fa4d1ba10fc4484431fd463e5c

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet

@pytest.mark.asyncio
async def test_multicall(get_starknet):
    starknet = get_starknet
    multicall = await deploy(starknet, "contracts/Multicall.cairo")
    erc20_1 = await deploy(starknet, "contracts/ERC20.cairo")
    erc20_2 = await deploy(starknet, "contracts/ERC20.cairo")

    await erc20_1.mint(user1, 100).invoke()
    await erc20_2.mint(user2, 200).invoke()

    contracts = [erc20_1.contract_address, erc20_1.contract_address, erc20_2.contract_address]
    selectors = [get_selector_from_name('decimals'), get_selector_from_name('balance_of'), get_selector_from_name('balance_of')]
    offsets = [0, 1, 1]
    calldata = [user1, user2]

    response = await multicall.multicall(contracts, selectors, offsets, calldata).call()
    assert response.result.result[0] == 18
    assert response.result.result[1] == 100
    assert response.result.result[2] == 200