from typing import Optional, List, Tuple
from starkware.starknet.public.abi import get_selector_from_name
from starkware.starknet.definitions.general_config import StarknetChainId
from starkware.starknet.testing.contract import StarknetContract, DeclaredClass
from starkware.starknet.core.os.transaction_hash.transaction_hash import calculate_transaction_hash_common, TransactionHashPrefix
from starkware.starknet.services.api.gateway.transaction import InvokeFunction, Declare, DeployAccount
from starkware.starknet.business_logic.transaction.objects import InternalTransaction, TransactionExecutionInfo
from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.core.os.class_hash import compute_class_hash
from starkware.starknet.testing.objects import StarknetCallInfo
from starkware.starknet.testing.starknet import Starknet
from utils.Signer import Signer

from test.utils.utilities import build_contract_with_proxy

TRANSACTION_VERSION = 1


# [target_address, selector, arguments]
Call = Tuple[str, str, List]


class TransactionSender:
    def __init__(self, account: StarknetContract):
        self.account = account

    @staticmethod
    def get_signature(
            message_hash: int,
            signer_keys: Signer,
            guardian_keys: Optional[Signer] = None,
            backup_guardian_keys:Optional[Signer] = None,
    ) -> List[int]:
        signers = [signer_keys]
        if guardian_keys is not None or backup_guardian_keys is not None:
            signers.append(guardian_keys)
        if backup_guardian_keys is not None:
            signers.append(backup_guardian_keys)

        signatures = []
        for signer in signers:
            if signer is None:
                signatures += [0, 0]
            else:
                signatures += list(signer.sign(message_hash))

        return signatures

    async def send_transaction(
        self,
        calls: List[Call],
        signers: List[Signer],
        nonce: Optional[int] = None,
        max_fee: Optional[int] = 0
    ) -> TransactionExecutionInfo:

        calls_with_selector = [(call[0], get_selector_from_name(call[1]), call[2]) for call in calls]
        call_array, calldata = from_call_to_call_array(calls)
        
        raw_invocation = self.account.__execute__(call_array, calldata)
        state = raw_invocation.state

        if nonce is None:
            nonce = await state.state.get_nonce_at(contract_address=self.account.contract_address)

        transaction_hash = get_transaction_hash(TransactionHashPrefix.INVOKE, self.account.contract_address, raw_invocation.calldata, nonce, max_fee)

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
    
    async def declare_class(
        self,
        contract_cls: ContractClass,
        signers: List[Signer],
        nonce: Optional[int] = None,
        max_fee: Optional[int] = 0
    ) -> TransactionExecutionInfo :
        
        state = self.account.state

        if nonce is None:
            nonce = await state.state.get_nonce_at(contract_address=self.account.contract_address)

        class_hash = compute_class_hash(contract_cls)
        transaction_hash = get_transaction_hash(TransactionHashPrefix.DECLARE, self.account.contract_address, [class_hash], nonce, max_fee)

        signatures = []
        for signer in signers:
            if signer == 0:
                signatures += [0, 0]
            else:    
                signatures += list(signer.sign(transaction_hash))

        external_tx = Declare(
            sender_address=self.account.contract_address,
            contract_class=contract_cls,
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

    @staticmethod
    async def deploy(
            starknet: Starknet,
            proxy_cls: ContractClass,
            proxy_decl: DeclaredClass,
            account_decl: DeclaredClass,
            account_cls: ContractClass,
            signer_keys: Signer,
            guardian_keys: Optional[Signer] = None
    ):

        unsigned_tx = await TransactionSender.get_unsigned_deploy_transaction(
            proxy_decl=proxy_decl,
            account_decl=account_decl,
            signer_pub_key=signer_keys.public_key,
            guardian_pub_key= None if guardian_keys is None else guardian_keys.public_key
        )

        signature = TransactionSender.get_signature(
            message_hash=unsigned_tx.calculate_hash(starknet.state.general_config),
            signer_keys=signer_keys,
            guardian_keys=guardian_keys
        )


        proxy = await TransactionSender.send_deploy_tx(
            starknet=starknet,
            unsigned_tx=unsigned_tx,
            contract_cls=proxy_cls,
            signature=signature
        )

        account = build_contract_with_proxy(proxy=proxy, implementation_abi=account_cls.abi),

        return TransactionSender(account)

    @staticmethod
    async def get_unsigned_deploy_transaction(
            proxy_decl: DeclaredClass,
            account_decl: DeclaredClass,
            signer_pub_key: int,
            guardian_pub_key: Optional[int] = None,
            salt: Optional[int] = None,
    ) -> DeployAccount:
        initialize_params = [signer_pub_key, 0 if guardian_pub_key is None else guardian_pub_key]
        proxy_call_data = [
            account_decl.class_hash,  # implementation,
            get_selector_from_name('initialize'),  # selector
            len(initialize_params),  # arguments to initialize method
            *initialize_params
        ]
        nonce = 0
        max_fee = 0

        external_tx = DeployAccount(
            class_hash=proxy_decl.class_hash,
            contract_address_salt=0 if salt is None else salt,
            constructor_calldata=proxy_call_data,
            version=TRANSACTION_VERSION,
            nonce=nonce,
            max_fee=max_fee,
            signature=[]
        )
        return external_tx

    @staticmethod
    async def send_deploy_tx(starknet: Starknet, unsigned_tx: DeployAccount, contract_cls: ContractClass, signature: List[int]) -> StarknetContract:
        external_tx = DeployAccount(
            class_hash=unsigned_tx.class_hash,
            contract_address_salt=unsigned_tx.contract_address_salt,
            constructor_calldata=unsigned_tx.constructor_calldata,
            version=unsigned_tx.version,
            nonce=unsigned_tx.nonce,
            max_fee=unsigned_tx.max_fee,
            signature=signature
        )
        tx_exec_info = await starknet.state.execute_tx(tx=InternalTransaction.from_external(
                external_tx=external_tx,
                general_config=starknet.state.general_config
        ))

        return StarknetContract(
            state=starknet.state,
            abi=contract_cls.abi,
            contract_address=tx_exec_info.call_info.contract_address,
            deploy_call_info=StarknetCallInfo.from_internal(
                call_info=tx_exec_info.call_info,
                result=(),
                main_call_events=tx_exec_info.call_info.events
            )
        )


def from_call_to_call_array(calls: List[Call]):
    call_array = []
    calldata = []
    for call in calls:
        assert len(call) == 3, "Invalid call parameters"
        entry = (call[0], get_selector_from_name(call[1]), len(calldata), len(call[2]))
        call_array.append(entry)
        calldata.extend(call[2])
    return call_array, calldata

def get_transaction_hash(prefix, account, calldata, nonce, max_fee):
    
    additional_data = [nonce]

    return calculate_transaction_hash_common(
            tx_hash_prefix=prefix,
            version=TRANSACTION_VERSION,
            contract_address=account,
            entry_point_selector=0,
            calldata=calldata,
            max_fee=max_fee,
            chain_id=StarknetChainId.TESTNET.value,
            additional_data=additional_data,
    )
