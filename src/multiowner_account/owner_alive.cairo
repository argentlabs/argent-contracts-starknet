use argent::offchain_message::{IOffChainMessageHashRev1, IStructHashRev1, StarknetDomain};
use argent::signer::signer_signature::SignerSignature;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use starknet::{get_contract_address, get_tx_info};


#[derive(Drop, Copy, Hash)]
pub struct OwnerAlive {
    pub new_owner_guid: felt252,
    pub signature_expiration: u64,
}

///  Required to prevent changing to an owner which is not in control of the user
#[derive(Drop, Copy, Serde)]
pub struct OwnerAliveSignature {
    /// It is the signature of the SNIP-12 V1 compliant object OwnerAlive
    pub owner_signature: SignerSignature,
    /// Signature expiration in seconds. Cannot be more than 24 hours in the future
    pub signature_expiration: u64,
}


const OWNER_ALIVE_TYPE_HASH: felt252 = selector!(
    "\"Owner Alive\"(\"Owner GUID\":\"felt\",\"Signature expiration\":\"timestamp\")",
);


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
