use hash::{HashStateExTrait, HashStateTrait};
use pedersen::PedersenTrait;
use poseidon::poseidon_hash_span;

trait IOffChainMessageHashRev0<T> {
    fn get_message_hash_rev_0(self: @T) -> felt252;
}

trait IOffChainMessageHashRev1<T> {
    fn get_message_hash_rev_1(self: @T) -> felt252;
}

trait IStructHashRev0<T> {
    fn get_struct_hash_rev_0(self: @T) -> felt252;
}

trait IStructHashRev1<T> {
    fn get_struct_hash_rev_1(self: @T) -> felt252;
}

// needed for session
trait IMerkleLeafHash<T> {
    fn get_merkle_leaf(self: @T) -> felt252;
}

// SNIP 12 Revision 0
#[derive(Copy, Drop, Hash)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}

const STARKNET_DOMAIN_TYPE_HASH_REV_0: felt252 = selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");

// TODO: perhaps add negative impl of IStructHash? 
// impl StructHashStarknetDomain<-IStructHash<StarkNetDomain>> of IStarknetDomainHash<StarkNetDomain>
impl StructHashStarkNetDomain of IStructHashRev0<StarkNetDomain> {
    fn get_struct_hash_rev_0(self: @StarkNetDomain) -> felt252 {
        PedersenTrait::new(0).update_with(STARKNET_DOMAIN_TYPE_HASH_REV_0).update_with(*self).update_with(4).finalize()
    }
}

// SNIP 12 REV 1
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
