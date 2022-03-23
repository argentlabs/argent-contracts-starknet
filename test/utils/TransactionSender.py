from starkware.starknet.public.abi import get_selector_from_name
from starkware.cairo.common.hash_state import compute_hash_on_elements
from starkware.starknet.definitions.general_config import StarknetChainId
from starkware.starknet.core.os.transaction_hash import TransactionHashPrefix
import logging
from utils.utilities import str_to_felt

LOGGER = logging.getLogger(__name__)

TRANSACTION_VERSION = 0

class TransactionSender():
    def __init__(self, account):
        self.account = account

    async def send_transaction(self, calls, signers, nonce=None, max_fee=0):
        if nonce is None:
            execution_info = await self.account.get_nonce().call()
            nonce = execution_info.result.nonce

        calls_with_selector = [(call[0], get_selector_from_name(call[1]), call[2]) for call in calls]
        call_array, calldata = from_call_to_call_array(calls)

        transaction_hash = get_transaction_hash(self.account.contract_address, call_array, calldata, nonce, max_fee)

        signatures = []
        for signer in signers:
            if signer == 0:
                signatures += [0, 0]
            else:    
                signatures += list(signer.sign(transaction_hash))

        return await self.account.__execute__(call_array, calldata, nonce).invoke(signature=signatures)

def from_call_to_call_array(calls):
    call_array = []
    calldata = []
    for call in calls:
        assert len(call) == 3, "Invalid call parameters"
        entry = (call[0], get_selector_from_name(call[1]), len(calldata), len(call[2]))
        call_array.append(entry)
        calldata.extend(call[2])
    return call_array, calldata

def get_transaction_hash(account, call_array, calldata, nonce, max_fee):
    execute_calldata = [
        len(call_array),
        *[x for t in call_array for x in t],
        len(calldata),
        *calldata,
        nonce]

    data_to_hash = [
        TransactionHashPrefix.INVOKE.value,
        TRANSACTION_VERSION,
        account,
        get_selector_from_name('__execute__'),
        compute_hash_on_elements(execute_calldata),
        max_fee,
        StarknetChainId.TESTNET.value,
    ]
    return compute_hash_on_elements(data_to_hash)