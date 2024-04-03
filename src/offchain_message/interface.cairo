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


// mainnet_domain_hash = 396976932011104915691903508476593435452325164665257511598712881532315662893;
// result of hades_permutation('StarkNet Message', mainnet_domain_hash, 0);
const MAINNET_FIRST_HADES_PERMUTATION_REV_1: (felt252, felt252, felt252) =
    (
        2323134905843710400277850554467420438836802451436694979291226432262210349922,
        497047802536209445013847976375993952138881488253153206740640135894961444223,
        1534648249535688540587269261500462862519297145299981583675973457661163002808
    );


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
