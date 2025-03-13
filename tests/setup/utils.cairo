use argent::signer::signer_signature::{Signer, SignerSignature, SignerTrait, StarknetSignature, StarknetSigner};
use argent::utils::serialization::serialize;
use snforge_std::{CheatSpan, cheat_chain_id, cheat_transaction_version};
use starknet::ContractAddress;
use super::constants::KeyAndSig;

fn to_starknet_signer_signatures(arr: Array<felt252>) -> Array<felt252> {
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

fn to_starknet_signatures(arr: Array<KeyAndSig>) -> Array<felt252> {
    let mut signatures = array![];
    let mut arr = arr.span();
    while let Option::Some(item) = arr.pop_front() {
        let pubkey = (*item.pubkey).try_into().expect('argent/zero-pubkey');
        let StarknetSignature { r, s } = *item.sig;
        signatures.append(SignerSignature::Starknet((pubkey, StarknetSignature { r, s })));
    };
    serialize(@signatures)
}

fn set_tx_version_foundry(version: felt252, address: ContractAddress) {
    cheat_transaction_version(address, version, CheatSpan::Indefinite(()));
}

fn set_chain_id_foundry(chain_id: felt252) {
    cheat_chain_id(0.try_into().unwrap(), chain_id, CheatSpan::Indefinite(()));
}

impl felt252TryIntoStarknetSigner of TryInto<felt252, StarknetSigner> {
    #[inline(always)]
    fn try_into(self: felt252) -> Option<StarknetSigner> {
        Option::Some(StarknetSigner { pubkey: self.try_into().expect('Cant create starknet signer') })
    }
}

