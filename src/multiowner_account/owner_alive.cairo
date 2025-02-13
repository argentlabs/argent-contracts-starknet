use argent::offchain_message::{IOffChainMessageHashRev1, IStructHashRev1, StarknetDomain};
use argent::signer::signer_signature::SignerSignature;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use starknet::{get_contract_address, get_tx_info};

/// @notice Message to sign proving a specific owner is still valid
/// @dev Prevents accidentally bricking the account by requiring proof that at least one remaining owner can sign
/// @param new_owner_guid GUID of the owner that must prove signing capability
/// @param signature_expiration Timestamp after which this proof becomes invalid
#[derive(Drop, Copy, Hash)]
pub struct OwnerAlive {
    pub new_owner_guid: felt252,
    pub signature_expiration: u64,
}

/// @notice Container for the signature and expiration of an OwnerAlive message
/// @param owner_signature Signature of the SNIP-12 V1 compliant OwnerAlive message
/// @param signature_expiration Timestamp when this proof expires
/// @dev The expiration must be within 24 hours of the transaction timestamp
#[derive(Drop, Copy, Serde)]
pub struct OwnerAliveSignature {
    pub owner_signature: SignerSignature,
    pub signature_expiration: u64,
}

/// @notice SNIP-12 V1 type hash for OwnerAlive message
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
