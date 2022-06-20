import os
from starkware.starknet.testing.contract import StarknetContract
from starkware.starknet.compiler.compile import compile_starknet_files
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starknet.business_logic.execution.objects import Event
from starkware.starknet.compiler.compile import get_selector_from_name

def str_to_felt(text):
    b_text = bytes(text, 'UTF-8')
    return int.from_bytes(b_text, "big")

def uint(a):
    return a, 0

async def assert_revert(expression, expected_message=None, expected_code=None):
    if expected_code is None:
        expected_code = StarknetErrorCode.TRANSACTION_FAILED
    try:
        await expression
        assert False
    except StarkException as err:
        _, error = err.args
        assert error['code'] == expected_code
        if expected_message is not None:
            assert expected_message in error['message']

def assert_event_emmited(tx_exec_info, from_address, name, data = []):
    if not data:
        raw_events = [Event(from_address=event.from_address, keys=event.keys, data=[]) for event in tx_exec_info.raw_events]
    else: 
        raw_events = tx_exec_info.raw_events  

    event = Event(
        from_address=from_address,
        keys=[get_selector_from_name(name)],
        data=data,
    )
    assert event in raw_events

    return event

contract_classes = {}

async def deploy(starknet, path, params=None):
    params = params or []
    if path in contract_classes:
        contract_class = contract_classes[path]
    else:
        contract_class = compile_starknet_files([path], debug_info=True)
        contract_classes[path] = contract_class
        await starknet.declare(contract_class=contract_class)
    deployed_contract = await starknet.deploy(contract_class=contract_class,constructor_calldata=params)
    return deployed_contract

async def declare(starknet, path):
    contract_class = compile_starknet_files([path], debug_info=True)
    declared_class = await starknet.declare(contract_class=contract_class)
    return declared_class

async def deploy_proxy(starknet, proxy_path, abi, params=None):
    params = params or []
    proxy_class = compile_starknet_files([proxy_path], debug_info=True)
    declared_proxy = await starknet.declare(contract_class=proxy_class)
    deployed_proxy = await starknet.deploy(contract_class=proxy_class, constructor_calldata=params)
    wrapped_proxy = StarknetContract(
        state=starknet.state,
        abi=abi,
        contract_address=deployed_proxy.contract_address,
        deploy_execution_info=deployed_proxy.deploy_execution_info)
    return deployed_proxy, wrapped_proxy