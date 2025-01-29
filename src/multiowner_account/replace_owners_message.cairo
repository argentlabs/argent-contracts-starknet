use argent::offchain_message::interface::{IOffChainMessageHashRev1, IStructHashRev1, StarknetDomain};
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use starknet::{get_contract_address, get_tx_info};


const REPLACE_OWNERS_WITH_ONE_TYPE_HASH: felt252 = selector!(
    "\"ReplaceOwnersWithOne\"(\"New owner GUID\":\"felt\",\"Signature expiration\":\"timestamp\")",
);

#[derive(Drop, Copy, Hash)]
pub struct ReplaceOwnersWithOne {
    pub new_owner_guid: felt252,
    pub signature_expiration: u64,
}

impl StructHashReplaceOwnersWithOneRev1 of IStructHashRev1<ReplaceOwnersWithOne> {
    fn get_struct_hash_rev_1(self: @ReplaceOwnersWithOne) -> felt252 {
        PoseidonTrait::new()
            .update_with(REPLACE_OWNERS_WITH_ONE_TYPE_HASH)
            .update_with(*self.new_owner_guid)
            .update_with(*self.signature_expiration.into())
            .finalize()
    }
}


impl OffChainMessageReplaceOwnersWithOneRev1 of IOffChainMessageHashRev1<ReplaceOwnersWithOne> {
    fn get_message_hash_rev_1(self: @ReplaceOwnersWithOne) -> felt252 {
        let chain_id = get_tx_info().chain_id;
        let domain = StarknetDomain { name: 'Replace all owners with one', version: '1', chain_id, revision: 1 };
        PoseidonTrait::new()
            .update_with('StarkNet Message')
            .update_with(domain.get_struct_hash_rev_1())
            .update_with(get_contract_address())
            .update_with((*self).get_struct_hash_rev_1())
            .finalize()
    }
}
