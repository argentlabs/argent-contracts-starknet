from typing import Tuple


from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.testing.contract import StarknetContract, DeclaredClass, StarknetContractFunctionInvocation

from test.utils.TransactionSender import TransactionSender
from utils.utilities import signer_key_1, signer_key_2, signer_key_3, signer_key_4, assert_revert


async def test_validate_deploy(deploy_env_copy: Tuple[Starknet, DeclaredClass, ContractClass, ContractClass, DeclaredClass]):
    starknet, account_decl, account_cls, proxy_cls, proxy_decl = deploy_env_copy

    unsigned_tx = await TransactionSender.get_unsigned_deploy_transaction(
        proxy_decl=proxy_decl,
        account_decl=account_decl,
        signer_pub_key=signer_key_1.public_key
    )
    signature = TransactionSender.get_signature(
        unsigned_tx.calculate_hash(starknet.state.general_config),
        signer_keys=signer_key_1
    )
    await TransactionSender.send_deploy_tx(
        starknet=starknet,
        unsigned_tx=unsigned_tx,
        contract_cls=proxy_cls,
        signature=signature
    )
