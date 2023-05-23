from typing import Tuple


from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.testing.contract import DeclaredClass

from utils.TransactionSender import TransactionSender
from utils.utilities import signer_key_1, signer_key_2, signer_key_3, signer_key_4, assert_revert, \
    build_contract_with_proxy


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
    proxy = await TransactionSender.send_deploy_tx(
        starknet=starknet,
        unsigned_tx=unsigned_tx,
        contract_cls=proxy_cls,
        signature=signature
    )
    account = build_contract_with_proxy(proxy=proxy, implementation_abi=account_cls.abi)
    assert (await account.getSigner().call()).result.signer == signer_key_1.public_key
    assert (await account.getGuardian().call()).result.guardian == 0


async def test_validate_deploy_with_guardian(deploy_env_copy: Tuple[Starknet, DeclaredClass, ContractClass, ContractClass, DeclaredClass]):
    starknet, account_decl, account_cls, proxy_cls, proxy_decl = deploy_env_copy

    unsigned_tx = await TransactionSender.get_unsigned_deploy_transaction(
        proxy_decl=proxy_decl,
        account_decl=account_decl,
        signer_pub_key=signer_key_1.public_key,
        guardian_pub_key=signer_key_2.public_key
    )
    signature = TransactionSender.get_signature(
        unsigned_tx.calculate_hash(starknet.state.general_config),
        signer_keys=signer_key_1,
        guardian_keys=signer_key_2
    )
    proxy = await TransactionSender.send_deploy_tx(
        starknet=starknet,
        unsigned_tx=unsigned_tx,
        contract_cls=proxy_cls,
        signature=signature
    )
    account = build_contract_with_proxy(proxy=proxy, implementation_abi=account_cls.abi)
    assert (await account.getSigner().call()).result.signer == signer_key_1.public_key
    assert (await account.getGuardian().call()).result.guardian == signer_key_2.public_key


async def test_validate_deploy_errors(deploy_env_copy: Tuple[Starknet, DeclaredClass, ContractClass, ContractClass, DeclaredClass]):
    starknet, account_decl, account_cls, proxy_cls, proxy_decl = deploy_env_copy

    unsigned_tx = await TransactionSender.get_unsigned_deploy_transaction(
        proxy_decl=proxy_decl,
        account_decl=account_decl,
        signer_pub_key=signer_key_1.public_key,
        guardian_pub_key=signer_key_2.public_key
    )

    tx_hash = unsigned_tx.calculate_hash(starknet.state.general_config)

    # Test with empty signature
    await assert_revert(
        TransactionSender.send_deploy_tx(
            starknet=starknet,
            unsigned_tx=unsigned_tx,
            contract_cls=proxy_cls,
            signature=[]
        ),
        expected_message="argent: signature format invalid"
    )

    # Test with signer only
    signer_only_sig = TransactionSender.get_signature(
        tx_hash,
        signer_keys=signer_key_1,
    )
    await assert_revert(
        TransactionSender.send_deploy_tx(
            starknet=starknet,
            unsigned_tx=unsigned_tx,
            contract_cls=proxy_cls,
            signature=signer_only_sig
        ),
        expected_message="argent: signature format invalid"
    )

    # Test with signer + 0 guardian signature
    await assert_revert(
        TransactionSender.send_deploy_tx(
            starknet=starknet,
            unsigned_tx=unsigned_tx,
            contract_cls=proxy_cls,
            signature=signer_only_sig + [0, 0]
        ),
        expected_message="argent: guardian signature invalid"
    )

    # Test with guardian only
    guardian_only_sig = TransactionSender.get_signature(
        tx_hash,
        signer_keys=signer_key_2,
        guardian_keys=signer_key_2
    )
    await assert_revert(
        TransactionSender.send_deploy_tx(
            starknet=starknet,
            unsigned_tx=unsigned_tx,
            contract_cls=proxy_cls,
            signature=guardian_only_sig
        ),
        expected_message="argent: signer signature invalid"
    )

    # Test with 0 signer signature + guardian
    await assert_revert(
        TransactionSender.send_deploy_tx(
            starknet=starknet,
            unsigned_tx=unsigned_tx,
            contract_cls=proxy_cls,
            signature=[0, 0] + guardian_only_sig
        ),
        expected_message="argent: signer signature invalid"
    )
