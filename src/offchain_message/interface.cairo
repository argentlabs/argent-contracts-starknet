use hash::{HashStateExTrait, HashStateTrait};
use pedersen::PedersenTrait;
use poseidon::poseidon_hash_span;

/// Reference to SNIP-12: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-12.md

/// @notice Defines the function to generate the SNIP-12 revision 0 compliant message hash
trait IOffChainMessageHashRev0<T> {
    fn get_message_hash_rev_0(self: @T) -> felt252;
}

/// @notice Defines the function to generate the SNIP-12 revision 1 compliant message hash
trait IOffChainMessageHashRev1<T> {
    fn get_message_hash_rev_1(self: @T) -> felt252;
}

/// @notice Defines the function to generates the SNIP-12 revision 0 compliant hash on an object
trait IStructHashRev0<T> {
    fn get_struct_hash_rev_0(self: @T) -> felt252;
}

/// @notice Defines the function to generates the SNIP-12 revision 1 compliant hash on an object
trait IStructHashRev1<T> {
    fn get_struct_hash_rev_1(self: @T) -> felt252;
}

/// @dev required for session
trait IMerkleLeafHash<T> {
    fn get_merkle_leaf(self: @T) -> felt252;
}

/// @notice StarkNetDomain using SNIP 12 Revision 0
#[derive(Copy, Drop, Hash)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}

const STARKNET_DOMAIN_TYPE_HASH_REV_0: felt252 = selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");

impl StructHashStarkNetDomain of IStructHashRev0<StarkNetDomain> {
    fn get_struct_hash_rev_0(self: @StarkNetDomain) -> felt252 {
        PedersenTrait::new(0).update_with(STARKNET_DOMAIN_TYPE_HASH_REV_0).update_with(*self).update_with(4).finalize()
    }
}

/// @notice StarkNetDomain using SNIP 12 Revision 1
#[derive(Hash, Drop, Copy)]
struct StarknetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
    revision: felt252,
}

const STARKNET_DOMAIN_TYPE_HASH_REV_1: felt252 =
    selector!(
        "\"StarknetDomain\"(\"name\":\"shortstring\",\"version\":\"shortstring\",\"chainId\":\"shortstring\",\"revision\":\"shortstring\")"
    );

impl StructHashStarknetDomain of IStructHashRev1<StarknetDomain> {
    fn get_struct_hash_rev_1(self: @StarknetDomain) -> felt252 {
        poseidon_hash_span(
            array![STARKNET_DOMAIN_TYPE_HASH_REV_1, *self.name, *self.version, *self.chain_id, *self.revision].span()
        )
    }
}
