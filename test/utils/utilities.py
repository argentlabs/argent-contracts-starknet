import os
from starkware.starknet.testing.contract import StarknetContract
from starkware.starknet.compiler.compile import compile_starknet_files
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starknet.business_logic.transaction_execution_objects import Event
from starkware.starknet.compiler.compile import get_selector_from_name

def str_to_felt(text):
    b_text = bytes(text, 'UTF-8')
    return int.from_bytes(b_text, "big")

def uint(a):
    return(a, 0)

async def assert_revert(expression):
    try:
        await expression
        assert False
    except StarkException as err:
        _, error = err.args
        assert error['code'] == StarknetErrorCode.TRANSACTION_FAILED

def assert_event_emmited(tx_exec_info, from_address, name, data):
    assert Event(
        from_address=from_address,
        keys=[get_selector_from_name(name)],
        data=data,
    ) in tx_exec_info.raw_events

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