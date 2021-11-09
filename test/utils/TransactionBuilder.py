from starkware.crypto.signature.signature import pedersen_hash, private_to_stark_key, sign
from starkware.starknet.public.abi import get_selector_from_name

class TransactionBuilder():
    def __init__(self, account, signer, guardian):
        self.account = account
        self.signer = signer
        self.guardian = guardian

    def build_execute_transaction(self, to, selector_name, calldata, nonce):
        selector = get_selector_from_name(selector_name)
        message_hash = hash_message(self.account.contract_address, to, selector, calldata, nonce)
        signatures = list(self.signer.sign(message_hash))
        if self.guardian != 0:
            signatures += list(self.guardian.sign(message_hash))
        return (self.account.execute(to, selector, calldata, nonce), signatures)

    def build_change_signer_transaction(self, new_signer, nonce):
        selector = get_selector_from_name('change_signer')
        message_hash = hash_message(self.account.contract_address, self.account.contract_address, selector, [new_signer], nonce)
        signatures = list(self.signer.sign(message_hash) + self.guardian.sign(message_hash))
        transaction = self.account.change_signer(new_signer, nonce)
        return (transaction, signatures)

    def build_change_guardian_transaction(self, new_guardian, nonce):
        selector = get_selector_from_name('change_guardian')
        message_hash = hash_message(self.account.contract_address, self.account.contract_address, selector, [new_guardian], nonce)
        signatures = list(self.signer.sign(message_hash) + self.guardian.sign(message_hash))
        transaction =  self.account.change_guardian(new_guardian, nonce)
        return (transaction, signatures)
        
    def build_change_L1_address_transaction(self, new_L1_address, nonce):
        selector = get_selector_from_name('change_L1_address')
        message_hash = hash_message(self.account.contract_address, self.account.contract_address, selector, [new_L1_address], nonce)
        signatures = list(self.signer.sign(message_hash) + self.guardian.sign(message_hash))
        transaction = self.account.change_L1_address(new_L1_address, nonce)
        return (transaction, signatures)

    def build_trigger_escape_transaction(self, escapor_signer, nonce):
        selector = get_selector_from_name('trigger_escape')
        message_hash = hash_message(self.account.contract_address, self.account.contract_address, selector, [escapor_signer.public_key], nonce)
        signatures = list(escapor_signer.sign(message_hash))
        transaction = self.account.trigger_escape(escapor_signer.public_key, nonce)
        return (transaction, signatures)

    def build_escape_guardian_transaction(self, new_guardian, nonce):
        selector = get_selector_from_name('escape_guardian')
        message_hash = hash_message(self.account.contract_address, self.account.contract_address, selector, [new_guardian.public_key], nonce)
        signatures  = list(self.signer.sign(message_hash))
        transaction = self.account.escape_guardian(new_guardian.public_key, nonce)
        return (transaction, signatures)

    def build_escape_signer_transaction(self, new_signer, nonce):
        selector = get_selector_from_name('escape_signer')
        message_hash = hash_message(self.account.contract_address, self.account.contract_address, selector, [new_signer.public_key], nonce)
        signatures = list(self.guardian.sign(message_hash))
        transaction = self.account.escape_signer(new_signer.public_key, nonce)
        return (transaction, signatures)

    def build_is_valid_signature_transaction(self, hash):
        signatures = list(self.signer.sign(hash) + self.guardian.sign(hash))
        return self.account.is_valid_signature(hash, signatures)

    async def get_nonce(self):
        return (await self.account.get_nonce().call()).result.nonce

    async def set_block_timestamp(self, timestamp):
        await self.account.set_block_timestamp(timestamp).invoke()

def hash_message(account, to, selector, calldata, nonce):
    res = pedersen_hash(account, to)
    res = pedersen_hash(res, selector)
    res_calldata = hash_calldata(calldata)
    res = pedersen_hash(res, res_calldata)
    return pedersen_hash(res, nonce)

def hash_calldata(calldata):
    if len(calldata) == 0:
        return 0
    elif len(calldata) == 1:
        return calldata[0]
    else:
        return pedersen_hash(hash_calldata(calldata[1:]), calldata[0])