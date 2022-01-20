import os
from starkware.starknet.testing.contract import StarknetContract
from starkware.starknet.compiler.compile import compile_starknet_files

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