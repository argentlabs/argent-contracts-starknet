use argent::offchain_message::interface::{IOffChainMessageHashRev1, IStructHashRev1, StarknetDomain};
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use starknet::{get_contract_address, get_tx_info};


const OWNER_ALIVE_TYPE_HASH: felt252 = selector!(
    "\"Owner Alive\"(\"Owner GUID\":\"felt\",\"Signature expiration\":\"timestamp\")",
);

#[derive(Drop, Copy, Hash)]
pub struct OwnerAlive {
    pub new_owner_guid: felt252,
    pub signature_expiration: u64,
}

impl StructHashOwnerAliveRev1 of IStructHashRev1<OwnerAlive> {
    fn get_struct_hash_rev_1(self: @OwnerAlive) -> felt252 {
        PoseidonTrait::new()
            .update_with(OWNER_ALIVE_TYPE_HASH)
            .update_with(*self.new_owner_guid)
            .update_with(*self.signature_expiration.into())
            .finalize()
    }
}


impl OffChainMessageOwnerAliveRev1 of IOffChainMessageHashRev1<OwnerAlive> {
    fn get_message_hash_rev_1(self: @OwnerAlive) -> felt252 {
        let chain_id = get_tx_info().chain_id;
        let domain = StarknetDomain { name: 'Owner Alive', version: '1', chain_id, revision: 1 };
        PoseidonTrait::new()
            .update_with('StarkNet Message')
            .update_with(domain.get_struct_hash_rev_1())
            .update_with(get_contract_address())
            .update_with((*self).get_struct_hash_rev_1())
            .finalize()
    }
}
