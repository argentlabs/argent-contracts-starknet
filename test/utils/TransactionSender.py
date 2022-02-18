from starkware.starknet.public.abi import get_selector_from_name
from starkware.cairo.common.hash_state import compute_hash_on_elements
import logging
from utils.utilities import str_to_felt

LOGGER = logging.getLogger(__name__)

PREFIX_TRANSACTION = str_to_felt('StarkNet Transaction')
TRANSACTION_VERSION = 0

class TransactionSender():
    def __init__(self, account):
        self.account = account

    async def send_transaction(self, calls, signers, nonce=None, max_fee=0):
        if nonce is None:
            execution_info = await self.account.get_nonce().call()
            nonce = execution_info.result.nonce

        mcalls = []
        calls_with_selector = []
        calldata = []
        for i in range(len(calls)):
            if len(calls[i]) != 3:
                raise Exception("Invalid call parameters")
            call = calls[i]
            mcall = (call[0], get_selector_from_name(call[1]), len(calldata), len(call[2]))
            mcalls.append(mcall)
            calldata.extend(call[2])
            calls_with_selector.append((call[0], get_selector_from_name(call[1]), call[2]))

        message_hash = hash_multicall(self.account.contract_address, calls_with_selector, nonce, max_fee)
        signatures = []
        for signer in signers:
            if signer == 0:
                signatures += list([0, 0])
            else:    
                signatures += list(signer.sign(message_hash))

        return await self.account.__execute__(mcalls, calldata, nonce).invoke(signature=signatures)

def hash_multicall(account, calls, nonce, max_fee):
    hash_array = []
    for call in calls:
        call_elements = [call[0], call[1], compute_hash_on_elements(call[2])]
        hash_array.append(compute_hash_on_elements(call_elements))

    message = [
        PREFIX_TRANSACTION,
        account,
        compute_hash_on_elements(hash_array),
        nonce,
        max_fee,
        TRANSACTION_VERSION
    ]
    return compute_hash_on_elements(message)