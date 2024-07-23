use argent::signer::signer_signature::{SignerSignature, StarknetSignature, StarknetSigner};
use argent::utils::serialization::serialize;
use snforge_std::{cheat_chain_id_global, cheat_transaction_version_global};
use starknet::ContractAddress;
use super::constants::KeyAndSig;

fn to_starknet_signer_signatures(arr: Array<felt252>) -> Array<felt252> {
    let mut signatures = array![];
    let mut arr = arr.span();
    while let Option::Some(item) = arr
        .pop_front() {
            let pubkey = (*item).try_into().expect('argent/zero-pubkey');
            let r = *arr.pop_front().unwrap();
            let s = *arr.pop_front().unwrap();
            signatures.append(SignerSignature::Starknet((pubkey, StarknetSignature { r, s })));
        };
    serialize(@signatures)
}

fn to_starknet_signatures(arr: Array<KeyAndSig>) -> Array<felt252> {
    let mut signatures = array![];
    let mut arr = arr.span();
    while let Option::Some(item) = arr
        .pop_front() {
            let pubkey = (*item.pubkey).try_into().expect('argent/zero-pubkey');
            let StarknetSignature { r, s } = *item.sig;
            signatures.append(SignerSignature::Starknet((pubkey, StarknetSignature { r, s })));
        };
    serialize(@signatures)
}

// TODO Remove those two fn and use the cheat directly?
fn set_tx_version_foundry(version: felt252, address: ContractAddress) {
    cheat_transaction_version_global(version);
}

fn set_chain_id_foundry(chain_id: felt252) {
    cheat_chain_id_global(chain_id);
}

impl felt252TryIntoStarknetSigner of TryInto<felt252, StarknetSigner> {
    #[inline(always)]
    fn try_into(self: felt252) -> Option<StarknetSigner> {
        Option::Some(StarknetSigner { pubkey: self.try_into().expect('Cant create starknet signer') })
    }
}

