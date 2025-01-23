use argent::offchain_message::interface::{StarknetDomain, IOffChainMessageHashRev1, IStructHashRev1};
use hash::{HashStateTrait, HashStateExTrait};
use poseidon::PoseidonTrait;
use starknet::{get_tx_info, get_contract_address};


const RESET_OWNERS_TYPE_HASH: felt252 =
    selector!("\"ResetOwners\"(\"New owner GUID\":\"felt\",\"Signature expiration\":\"timestamp\")");

#[derive(Drop, Copy, Hash)]
struct ResetOwners {
    new_owner_guid: felt252,
    signature_expiration: u64,
}

impl StructHashResetOwnersRev1 of IStructHashRev1<ResetOwners> {
    fn get_struct_hash_rev_1(self: @ResetOwners) -> felt252 {
        PoseidonTrait::new()
            .update_with(RESET_OWNERS_TYPE_HASH)
            .update_with(*self.new_owner_guid)
            .update_with(*self.signature_expiration.into())
            .finalize()
    }
}


impl OffChainMessageResetOwnersRev1 of IOffChainMessageHashRev1<ResetOwners> {
    fn get_message_hash_rev_1(self: @ResetOwners) -> felt252 {
        let chain_id = get_tx_info().chain_id;
        let domain = StarknetDomain { name: 'Replace all owners with one', version: '1', chain_id, revision: 1 };
        PoseidonTrait::new()
            .update_with('StarkNet Message')
            .update_with(domain.get_struct_hash_rev_1())
            .update_with(get_contract_address())
            .update_with((*self).get_struct_hash_rev_1())
            .finalize();
    }
}
