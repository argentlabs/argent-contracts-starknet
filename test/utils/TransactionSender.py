from starkware.starknet.public.abi import get_selector_from_name
from starkware.cairo.common.hash_state import compute_hash_on_elements

class TransactionSender():
    def __init__(self, account):
        self.account = account

    async def send_transaction(self, to, selector_name, calldata, signers, nonce=None):
        if nonce is None:
            execution_info = await self.account.get_nonce().call()
            nonce = execution_info.result.nonce

        selector = get_selector_from_name(selector_name)
        message_hash = hash_message(self.account.contract_address, to, selector, calldata, nonce)
        signatures = []
        for signer in signers:
            signatures += list(signer.sign(message_hash))

        return await self.account.execute(to, selector, calldata, nonce).invoke(signature=signatures)

    async def set_block_timestamp(self, timestamp):
        await self.account.set_block_timestamp(timestamp).invoke()

def hash_message(account, to, selector, calldata, nonce):
    message = [
        account,
        to,
        selector,
        compute_hash_on_elements(calldata),
        nonce
    ]
    return compute_hash_on_elements(message)