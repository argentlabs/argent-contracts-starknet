from abc import abstractmethod
from typing import Optional, List, Tuple
from starkware.crypto.signature.signature import sign
from starkware.starknet.testing.contract import StarknetContract
from starkware.starknet.definitions.general_config import StarknetChainId
from starkware.starknet.core.os.transaction_hash.transaction_hash import calculate_transaction_hash_common, TransactionHashPrefix
from starkware.starknet.services.api.gateway.transaction import InvokeFunction, Declare
from starkware.starknet.business_logic.transaction.objects import InternalTransaction, TransactionExecutionInfo
from starkware.starknet.compiler.compile import get_selector_from_name
from utils.Signer import Signer
from utils.utilities import from_call_to_call_array, cached_contract, copy_contract_state
TRANSACTION_VERSION = 1


class PluginSigner:
    def __init__(self, account: StarknetContract, plugin_address):
        self.account = account
        self.plugin_address = plugin_address

    @abstractmethod
    def sign(self, message_hash: int) -> List[int]:
        ...

    async def send_transaction(self, calls, nonce: Optional[int] = None, max_fee: Optional[int] = 0) -> TransactionExecutionInfo:
        return await self.send_signed_tx(await self.get_signed_transaction(calls, nonce, max_fee))

    async def send_signed_tx(self, signed_tx: InvokeFunction) -> TransactionExecutionInfo :
        return await self.account.state.execute_tx(
            tx=InternalTransaction.from_external(
                external_tx=signed_tx,
                general_config=self.account.state.general_config
            )
        )

    async def get_signed_transaction(self, calls, nonce: Optional[int] = None, max_fee: Optional[int] = 0) -> InvokeFunction:
        call_array, calldata = from_call_to_call_array(calls)

        account_copy = copy_contract_state(self.account)
        raw_invocation = account_copy.__execute__(call_array, calldata)

        if nonce is None:
            nonce = await raw_invocation.state.state.get_nonce_at(contract_address=account_copy.contract_address)

        transaction_hash = calculate_transaction_hash_common(
            tx_hash_prefix=TransactionHashPrefix.INVOKE,
            version=TRANSACTION_VERSION,
            contract_address=self.account.contract_address,
            entry_point_selector=0,
            calldata=raw_invocation.calldata,
            max_fee=max_fee,
            chain_id=StarknetChainId.TESTNET.value,
            additional_data=[nonce],
        )

        signature = self.sign(transaction_hash)

        external_tx = InvokeFunction(
            contract_address=self.account.contract_address,
            calldata=raw_invocation.calldata,
            entry_point_selector=None,
            signature=signature,
            max_fee=max_fee,
            version=TRANSACTION_VERSION,
            nonce=nonce,
        )
        return external_tx

    async def execute_on_plugin(self, selector_name, arguments=None, plugin=None):
        if arguments is None:
            arguments = []

        if plugin is None:
            plugin = self.plugin_address

        exec_arguments = [
            plugin,
            get_selector_from_name(selector_name),
            len(arguments),
            *arguments
        ]
        return await self.send_transaction([(self.account.contract_address, 'executeOnPlugin', exec_arguments)])

    async def read_on_plugin(self, selector_name, arguments=None, plugin=None):
        if arguments is None:
            arguments = []

        if plugin is None:
            plugin = self.plugin_address

        selector = get_selector_from_name(selector_name)
        return await self.account.executeOnPlugin(plugin, selector, arguments).call()

    async def add_plugin(self, plugin: int, plugin_arguments=None):
        if plugin_arguments is None:
            plugin_arguments = []
        return await self.send_transaction([(self.account.contract_address, 'addPlugin', [plugin, len(plugin_arguments), *plugin_arguments])])

    async def remove_plugin(self, plugin: int):
        return await self.send_transaction([(self.account.contract_address, 'removePlugin', [plugin])])
    
    async def getVersion(self):
        return await self.send_transaction([(self.account.contract_address, 'getVersion', [])])


class StarkPluginSigner(PluginSigner):
    def __init__(self, stark_key: Signer, account: StarknetContract, plugin_address):
        super().__init__(account, plugin_address)
        self.stark_key = stark_key
        self.public_key = stark_key.public_key

    def sign(self, message_hash: int) -> List[int]:
        return [self.plugin_address] + list(self.stark_key.sign(message_hash))