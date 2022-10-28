from starkware.cairo.common.hash_state import compute_hash_on_elements
from typing import Optional, List, Tuple
from starkware.starknet.compiler.compile import get_selector_from_name
from utils.utilities import str_to_felt
from utils.plugin_signer import PluginSigner, TRANSACTION_VERSION
from dataclasses import dataclass
from utils.utilities import from_call_to_call_array, copy_contract_state
from utils.Signer import Signer
from starkware.starknet.testing.contract import StarknetContract
from starkware.starknet.core.os.transaction_hash.transaction_hash import calculate_transaction_hash_common, TransactionHashPrefix
from starkware.starknet.business_logic.transaction.objects import InternalTransaction, TransactionExecutionInfo
from starkware.starknet.definitions.general_config import StarknetChainId
from starkware.starknet.services.api.gateway.transaction import InvokeFunction, Declare




class MultisigPluginSigner(PluginSigner):
    def __init__(self, keys: List[Signer], account: StarknetContract, plugin_address):
        super().__init__(account, plugin_address)
        self.keys = keys

    @staticmethod
    def get_owner_sig(message_hash: int, owner_keys: Signer) -> List[int]:
        return [owner_keys.public_key, *owner_keys.sign(message_hash)]

    def sign(self, message_hash: int) -> List[int]:
        signatures = [self.get_owner_sig(message_hash, owner_keys) for owner_keys in self.keys]
        signatures_flat = [item for signature in signatures for item in signature]
        return [self.plugin_address] + [len(signatures), *signatures_flat]


