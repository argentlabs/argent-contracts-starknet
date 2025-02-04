use core::hash::{HashStateExTrait, HashStateTrait};
use core::pedersen::PedersenTrait;
use core::poseidon::poseidon_hash_span;
use core::poseidon::{HashState, hades_permutation};
use starknet::get_contract_address;


/// Reference to SNIP-12: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-12.md

/// @notice Defines the function to generate the SNIP-12 revision 0 compliant message hash
pub trait IOffChainMessageHashRev0<T> {
    fn get_message_hash_rev_0(self: @T) -> felt252;
}

/// @notice Defines the function to generate the SNIP-12 revision 1 compliant message hash
pub trait IOffChainMessageHashRev1<T> {
    fn get_message_hash_rev_1(self: @T) -> felt252;
}

/// @notice Defines the function to generates the SNIP-12 revision 0 compliant hash on an object
pub trait IStructHashRev0<T> {
    fn get_struct_hash_rev_0(self: @T) -> felt252;
}

/// @notice Defines the function to generates the SNIP-12 revision 1 compliant hash on an object
pub trait IStructHashRev1<T> {
    fn get_struct_hash_rev_1(self: @T) -> felt252;
}

/// @dev required for session
pub trait IMerkleLeafHash<T> {
    fn get_merkle_leaf(self: @T) -> felt252;
}

/// @notice StarkNetDomain using SNIP 12 Revision 0
#[derive(Copy, Drop, Hash)]
pub struct StarkNetDomain {
    pub name: felt252,
    pub version: felt252,
    pub chain_id: felt252,
}

const STARKNET_DOMAIN_TYPE_HASH_REV_0: felt252 = selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");

pub impl StructHashStarkNetDomain of IStructHashRev0<StarkNetDomain> {
    fn get_struct_hash_rev_0(self: @StarkNetDomain) -> felt252 {
        PedersenTrait::new(0).update_with(STARKNET_DOMAIN_TYPE_HASH_REV_0).update_with(*self).update_with(4).finalize()
    }
}

/// @notice StarkNetDomain using SNIP 12 Revision 1
#[derive(Hash, Drop, Copy)]
pub struct StarknetDomain {
    pub name: felt252,
    pub version: felt252,
    pub chain_id: felt252,
    pub revision: felt252,
}

const STARKNET_DOMAIN_TYPE_HASH_REV_1: felt252 = selector!(
    "\"StarknetDomain\"(\"name\":\"shortstring\",\"version\":\"shortstring\",\"chainId\":\"shortstring\",\"revision\":\"shortstring\")",
);

pub impl StructHashStarknetDomain of IStructHashRev1<StarknetDomain> {
    fn get_struct_hash_rev_1(self: @StarknetDomain) -> felt252 {
        poseidon_hash_span(
            array![STARKNET_DOMAIN_TYPE_HASH_REV_1, *self.name, *self.version, *self.chain_id, *self.revision].span(),
        )
    }
}

pub fn get_message_hash_rev_1_with_precalc<T, +Drop<T>, +IStructHashRev1<T>>(
    hades_permutation_state: (felt252, felt252, felt252), rev1_struct: T,
) -> felt252 {
    // mainnet_domain_hash = domain.get_struct_hash_rev_1()
    // hades_permutation_state == hades_permutation('StarkNet Message', mainnet_domain_hash, 0);
    let (s0, s1, s2) = hades_permutation_state;

    let (fs0, fs1, fs2) = hades_permutation(
        s0 + get_contract_address().into(), s1 + rev1_struct.get_struct_hash_rev_1(), s2,
    );
    HashState { s0: fs0, s1: fs1, s2: fs2, odd: false }.finalize()
}
