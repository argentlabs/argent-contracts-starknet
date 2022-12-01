from typing import Tuple

import pytest
import asyncio

from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.testing.contract import DeclaredClass
from starkware.starknet.testing.starknet import Starknet
from utils.utilities import compile


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def starknet():
    return await Starknet.empty()


@pytest.fixture(scope='module')
def account_cls() -> ContractClass:
    return compile('contracts/account/ArgentAccount.cairo')


@pytest.fixture(scope='module')
def test_dapp_cls() -> ContractClass:
    return compile("contracts/test/TestDapp.cairo")


@pytest.fixture(scope='module')
async def proxy_cls() -> ContractClass:
    return compile("contracts/upgrade/Proxy.cairo")


@pytest.fixture(scope='module')
async def declared_account(starknet: Starknet, account_cls: ContractClass) -> DeclaredClass:
    return await starknet.declare(contract_class=account_cls)


@pytest.fixture(scope='module')
async def declared_proxy(starknet: Starknet, proxy_cls: ContractClass):
    return await starknet.declare(contract_class=proxy_cls)


@pytest.fixture(scope='module')
async def deploy_env(starknet: Starknet, declared_account: DeclaredClass, declared_proxy: DeclaredClass, proxy_cls: ContractClass, account_cls: ContractClass):
    return starknet, declared_account, account_cls, proxy_cls, declared_proxy


@pytest.fixture
def deploy_env_copy(deploy_env: Tuple[Starknet, DeclaredClass, ContractClass, ContractClass, DeclaredClass]):
    starknet, account_decl, account_cls, proxy_cls, proxy_decl = deploy_env
    starknet_copy = Starknet(starknet.state.copy())
    return starknet_copy, account_decl, account_cls, proxy_cls, proxy_decl