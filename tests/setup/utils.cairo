use argent::signer::signer_signature::{SignerSignature, StarknetSignature, StarknetSigner};
use argent::utils::serialization::serialize;
use crate::KeyAndSig;

pub fn to_starknet_signer_signatures(arr: Array<felt252>) -> Array<felt252> {
    let mut signatures = array![];
    let mut arr = arr.span();
    while let Option::Some(item) = arr.pop_front() {
        let pubkey = (*item).try_into().expect('argent/zero-pubkey');
        let r = *arr.pop_front().unwrap();
        let s = *arr.pop_front().unwrap();
        signatures.append(SignerSignature::Starknet((pubkey, StarknetSignature { r, s })));
    };
    serialize(@signatures)
}

pub fn to_starknet_signatures(arr: Array<KeyAndSig>) -> Array<felt252> {
    let mut signatures = array![];
    let mut arr = arr.span();
    for item in arr {
        let pubkey = (*item.pubkey).try_into().expect('argent/zero-pubkey');
        let StarknetSignature { r, s } = *item.sig;
        signatures.append(SignerSignature::Starknet((pubkey, StarknetSignature { r, s })));
    };
    serialize(@signatures)
}

pub impl Felt252TryIntoStarknetSigner of TryInto<felt252, StarknetSigner> {
    #[inline(always)]
    fn try_into(self: felt252) -> Option<StarknetSigner> {
        Option::Some(StarknetSigner { pubkey: self.try_into().expect('Cant create starknet signer') })
    }
}

#[generate_trait]
pub impl ByteArrayExt of ByteArrayExtTrait {
    fn into_bytes(self: ByteArray) -> Array<u8> {
        let len = self.len();
        let mut output = array![];
        let mut i = 0;
        while i != len {
            output.append(self[i]);
            i += 1;
        };
        output
    }
}
