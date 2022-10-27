from starkware.cairo.common.hash_state import compute_hash_on_elements
from typing import Optional, List, Tuple
from utils.merkle_utils import get_leaves, generate_merkle_root, generate_merkle_proof
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

AllowedCall = Tuple[int,str]
# H('StarkNetDomain(chainId:felt)')
STARKNET_DOMAIN_TYPE_HASH = 0x13cda234a04d66db62c06b8e3ad5f91bd0c67286c2c7519a826cf49da6ba478
# H('Session(key:felt,expires:felt,root:merkletree)')
SESSION_TYPE_HASH = 0x1aa0e1c56b45cf06a54534fa1707c54e520b842feb21d03b7deddb6f1e340c
# H(Policy(contractAddress:felt,selector:selector))
POLICY_TYPE_HASH = 0x2f0026e78543f036f33e26a8f5891b88c58dc1e20cbbfaf0bb53274da6fa568


# Returns the tree root and proofs for each allowed call
def generate_policy_tree(allowed_calls : List[AllowedCall]) -> Tuple[int, List[List[int]]]:
    merkle_leaves: List[Tuple[int, int, int]] = get_leaves(
        policy_type_hash=POLICY_TYPE_HASH,
        contracts=[a[0] for a in allowed_calls],
        selectors=[get_selector_from_name(a[1]) for a in allowed_calls],
    )
    leaves = [leave[0] for leave in merkle_leaves]
    root = generate_merkle_root(leaves)
    proofs = [generate_merkle_proof(leaves, index) for index, leave in enumerate(leaves)]
    return root, proofs


@dataclass
class Session:
    session_public_key: int
    session_expiration: int
    root: int
    allowed_calls: List[AllowedCall]
    proofs: List[List[int]]
    session_hash: int
    account_address: int
    session_token: List[int]

    def single_proof_len(self) -> int:
        return len(self.proofs[0])


def build_session(signer, allowed_calls: List[AllowedCall], session_public_key: int, session_expiration:int, chain_id:int, account_address: int):
    root, proofs = generate_policy_tree(allowed_calls)
    domain_hash = compute_hash_on_elements([STARKNET_DOMAIN_TYPE_HASH, chain_id])
    message_hash = compute_hash_on_elements([SESSION_TYPE_HASH, session_public_key, session_expiration, root])

    session_hash = compute_hash_on_elements([
        str_to_felt('StarkNet Message'),
        domain_hash,
        account_address,
        message_hash
    ])
    signed_hash = signer.sign(session_hash)
    return Session(
        session_public_key=session_public_key,
        session_expiration=session_expiration,
        root=root,
        allowed_calls=allowed_calls,
        proofs=proofs,
        session_hash=session_hash,
        account_address=account_address,
        session_token=signed_hash
    )


class SessionPluginSigner(PluginSigner):
    def __init__(self, stark_key: Signer, account: StarknetContract, plugin_address):
        super().__init__(account, plugin_address)
        self.stark_key = stark_key
        self.public_key = stark_key.public_key

    def sign(self, message_hash: int) -> List[int]:
        raise Exception("SessionPluginSigner can't sign arbitrary messages")

    async def get_signed_transaction(self, calls, session: Session, nonce: Optional[int] = None, max_fee: Optional[int] = 0) -> InvokeFunction:
        proofs = []
        for call in calls:
            call_proof_index = session.allowed_calls.index((call[0], call[1]))
            proofs.append(session.proofs[call_proof_index])
        return await self.get_signed_transaction_with_proofs(calls, session, proofs, nonce, max_fee)

    async def get_signed_transaction_with_proofs(self, calls, session: Session, proofs: List[List[int]], nonce: Optional[int] = None, max_fee: Optional[int] = 0) -> InvokeFunction:
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

        session_signature = self.stark_key.sign(transaction_hash)
        proofs_flat = [item for proof in proofs for item in proof]
        signature = [
            self.plugin_address,
            *session_signature,          # session signature
            session.session_public_key,  # session_key
            session.session_expiration,  # expiration
            session.root,                # root
            session.single_proof_len(),  # single_proof_len
            len(proofs_flat),            # proofs_len
            *proofs_flat,                # proofs
            len(session.session_token),  # session_token_len
            *session.session_token       # session_token
        ]

        return InvokeFunction(
            contract_address=self.account.contract_address,
            calldata=raw_invocation.calldata,
            entry_point_selector=None,
            signature=signature,
            max_fee=max_fee,
            version=TRANSACTION_VERSION,
            nonce=nonce,
        )

    async def send_transaction(self, calls, session: Session, nonce: Optional[int] = None, max_fee: Optional[int] = 0) -> TransactionExecutionInfo:
        signed_tx = await self.get_signed_transaction(calls, session, nonce, max_fee)
        return await self.send_signed_tx(signed_tx)

    async def send_transaction_with_proofs(self, calls, session: Session, proofs: List[List[int]], nonce: Optional[int] = None, max_fee: Optional[int] = 0) -> TransactionExecutionInfo :
        signed_tx = await self.get_signed_transaction_with_proofs(calls, session, proofs, nonce, max_fee)
        return await self.send_signed_tx(signed_tx)

    async def send_signed_tx(self, signed_tx: InvokeFunction) -> TransactionExecutionInfo:
        return await self.account.state.execute_tx(
            tx=InternalTransaction.from_external(
                external_tx=signed_tx,
                general_config=self.account.state.general_config
            )
        )
