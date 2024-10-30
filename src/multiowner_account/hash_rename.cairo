use argent::offchain_message::{
    interface::{StarknetDomain, StructHashStarkNetDomain, IOffChainMessageHashRev1, IStructHashRev1},
    precalculated_hashing::get_message_hash_rev_1_with_precalc
};

use hash::{HashStateTrait, HashStateExTrait};
use poseidon::{poseidon_hash_span, PoseidonTrait, hades_permutation, HashState};
use starknet::{get_tx_info, get_caller_address};


const SIMPLE_STRUCT_TYPE_HASH: felt252 =
    selector!("\"ReplaceOwnersWithOne\"(\"new_owner_guid\":\"felt\",\"signature_expiration\":\"u128\")");

#[derive(Drop, Copy, Hash)]
struct ReplaceOwnersWithOne {
    new_owner_guid: felt252,
    signature_expiration: u64,
}

impl StructHashReplaceOwnersWithOneRev1 of IStructHashRev1<ReplaceOwnersWithOne> {
    fn get_struct_hash_rev_1(self: @ReplaceOwnersWithOne) -> felt252 {
        PoseidonTrait::new()
            .update_with(SIMPLE_STRUCT_TYPE_HASH)
            .update_with(*self.new_owner_guid)
            .update_with(*self.signature_expiration.into())
            .finalize()
    }
}


impl OffChainMessageReplaceOwnersWithOneRev1 of IOffChainMessageHashRev1<ReplaceOwnersWithOne> {
    fn get_message_hash_rev_1(self: @ReplaceOwnersWithOne) -> felt252 {
        // Version is a felt instead of a shortstring in SNIP-9 due to a mistake in the Braavos contracts and has been
        // copied for compatibility.
        // Revision will also be a felt instead of a shortstring for all SNIP12-rev1 signatures because of the same
        // issue
        let chain_id = get_tx_info().chain_id;
        // name: Account.replace_all_owners_with_one is too long
        let domain = StarknetDomain { name: 'replace_all_owners_with_one', version: 1, chain_id, revision: 1 };
        poseidon_hash_span(
            array![
                'StarkNet Message',
                domain.get_struct_hash_rev_1(),
                get_caller_address().into(), // TODO Double check this correct?
                (*self).get_struct_hash_rev_1(),
            ]
                .span()
        )
    }
}
