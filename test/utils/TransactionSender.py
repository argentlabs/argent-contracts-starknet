from typing import Optional, List, Tuple
from starkware.starknet.public.abi import get_selector_from_name
from starkware.starknet.definitions.general_config import StarknetChainId
from starkware.starknet.testing.contract import StarknetContract
from starkware.starknet.core.os.transaction_hash.transaction_hash import calculate_transaction_hash_common, TransactionHashPrefix
from starkware.starknet.services.api.gateway.transaction import InvokeFunction
from starkware.starknet.business_logic.transaction.objects import InternalTransaction, TransactionExecutionInfo
from utils.Signer import Signer

TRANSACTION_VERSION = 1

class TransactionSender():
    def __init__(self, account: StarknetContract):
        self.account = account

    async def send_transaction(
        self,
        calls,
        signers: List[Signer],
        nonce: Optional[int] = None,
        max_fee: Optional[int] = 0
    ) -> TransactionExecutionInfo :

        calls_with_selector = [(call[0], get_selector_from_name(call[1]), call[2]) for call in calls]
        call_array, calldata = from_call_to_call_array(calls)
        
        raw_invocation = self.account.__execute__(call_array, calldata)
        state = raw_invocation.state

        if nonce is None:
            nonce = await state.state.get_nonce_at(contract_address=self.account.contract_address)

        transaction_hash = get_transaction_hash(self.account.contract_address, raw_invocation.calldata, nonce, max_fee)

        signatures = []
        for signer in signers:
            if signer == 0:
                signatures += [0, 0]
            else:    
                signatures += list(signer.sign(transaction_hash))

        external_tx = InvokeFunction(
            contract_address=self.account.contract_address,
            calldata=raw_invocation.calldata,
            entry_point_selector=None,
            signature=signatures,
            max_fee=max_fee,
            version=TRANSACTION_VERSION,
            nonce=nonce,
        )

        tx = InternalTransaction.from_external(
            external_tx=external_tx, general_config=state.general_config
        )
        execution_info = await state.execute_tx(tx=tx)
        return execution_info

def from_call_to_call_array(calls):
    call_array = []
    calldata = []
    for call in calls:
        assert len(call) == 3, "Invalid call parameters"
        entry = (call[0], get_selector_from_name(call[1]), len(calldata), len(call[2]))
        call_array.append(entry)
        calldata.extend(call[2])
    return call_array, calldata

def get_transaction_hash(account, calldata, nonce, max_fee):
    
    additional_data = [nonce]

    return calculate_transaction_hash_common(
            tx_hash_prefix=TransactionHashPrefix.INVOKE,
            version=TRANSACTION_VERSION,
            contract_address=account,
            entry_point_selector=0,
            calldata=calldata,
            max_fee=max_fee,
            chain_id=StarknetChainId.TESTNET.value,
            additional_data=additional_data,
    )
