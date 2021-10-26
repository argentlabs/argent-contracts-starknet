from starkware.crypto.signature.signature import pedersen_hash, private_to_stark_key, sign
from starkware.starknet.public.abi import get_selector_from_name


class Signer():
    def __init__(self, private_key):
        self.private_key = private_key
        self.public_key = private_to_stark_key(private_key)

    def sign(self, message_hash):
        return sign(msg_hash=message_hash, priv_key=self.private_key)

