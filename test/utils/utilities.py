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

    assert Event(
        from_address=from_address,
        keys=[get_selector_from_name(name)],
        data=data,
    ) in raw_events

compiled_code = {}

async def deploy(starknet, path, params=None):
    params = params or []
    if path in compiled_code:
        contract_definition = compiled_code[path]
    else:
        contract_definition = compile_starknet_files([path], debug_info=True)
        compiled_code[path] = contract_definition
    deployed_contract = await starknet.deploy(contract_def=contract_definition,constructor_calldata=params)
    return deployed_contract

async def deploy_proxy(starknet, proxy_path, implementation_path, params=None):
    params = params or []
    proxy_definition = compile_starknet_files([proxy_path], debug_info=True)
    implementation_definition = compile_starknet_files([implementation_path], debug_info=True)
    deployed_proxy = await starknet.deploy(contract_def=proxy_definition, constructor_calldata=params)
    wrapped_proxy = StarknetContract(
        state=starknet.state,
        abi=implementation_definition.abi,
        contract_address=deployed_proxy.contract_address,
        deploy_execution_info=deployed_proxy.deploy_execution_info)
    return deployed_proxy, wrapped_proxy