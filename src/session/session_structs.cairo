use hash::{HashStateTrait, HashStateExTrait, LegacyHash, Hash};
use pedersen::PedersenTrait;
use starknet::account::Call;
use starknet::{get_tx_info, get_contract_address, ContractAddress};


#[derive(Drop, Serde, Copy)]
struct StarknetSignature {
    r: felt252,
    s: felt252,
}

#[derive(Drop, Serde, Copy)]
struct Session {
    expires_at: u64,
    allowed_methods_root: felt252,
    guardian_key: felt252,
    session_key: felt252,
}

#[derive(Drop, Serde, Copy)]
struct SessionToken {
    session: Session,
    account_signature: Span<felt252>,
    session_signature: StarknetSignature,
    backend_signature: StarknetSignature,
    proofs: Span<Span<felt252>>,
}

#[derive(Hash, Drop, Copy)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}

// update these once SNIP-12 is merged (i.e. use StarknetDomain)
const STARKNET_DOMAIN_TYPE_HASH: felt252 = selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");
const SESSION_TYPE_HASH: felt252 =
    selector!("Session(Expires At:timestamp,Allowed Methods:merkletree,Guardian Key:felt,Session Key:felt)");
const ALLOWED_METHOD_HASH: felt252 = selector!("Allowed Method(Contract Address:ContractAddress,selector:selector)");


trait IOffchainMessageHash<T> {
    fn get_message_hash(self: @T) -> felt252;
}

trait IStructHash<T> {
    fn get_struct_hash(self: @T) -> felt252;
}

trait IMerkleLeafHash<T> {
    fn get_merkle_leaf(self: @T) -> felt252;
}

impl MerkleLeafHash of IMerkleLeafHash<Call> {
    fn get_merkle_leaf(self: @Call) -> felt252 {
        let mut state = PedersenTrait::new(0);
        state = state.update_with(ALLOWED_METHOD_HASH);
        state = state.update_with(*self.to);
        state = state.update_with(*self.selector);
        state = state.update_with(3);
        state.finalize()
    }
}


impl StructHashSession of IStructHash<Session> {
    fn get_struct_hash(self: @Session) -> felt252 {
        let mut state = PedersenTrait::new(0);
        state = state.update_with(SESSION_TYPE_HASH);
        state = state.update_with(*self.expires_at);
        state = state.update_with(*self.allowed_methods_root);
        state = state.update_with(*self.guardian_key);
        state = state.update_with(*self.session_key);
        state = state.update_with(5);
        state.finalize()
    }
}


impl StructHashStarknetDomain of IStructHash<StarkNetDomain> {
    fn get_struct_hash(self: @StarkNetDomain) -> felt252 {
        let mut state = PedersenTrait::new(0);
        state = state.update_with(STARKNET_DOMAIN_TYPE_HASH);
        state = state.update_with(*self);
        state = state.update_with(4);
        state.finalize()
    }
}

impl OffchainMessageHashSession of IOffchainMessageHash<Session> {
    fn get_message_hash(self: @Session) -> felt252 {
        let domain = StarkNetDomain {
            name: 'SessionAccount.session', version: 1, chain_id: get_tx_info().unbox().chain_id
        };
        let mut state = PedersenTrait::new(0);
        state = state.update_with('StarkNet Message');
        state = state.update_with(domain.get_struct_hash());
        state = state.update_with(get_contract_address());
        state = state.update_with(self.get_struct_hash());
        state = state.update_with(4);
        state.finalize()
    }
}

impl StructHashSpanContract of IStructHash<ContractAddress> {
    fn get_struct_hash(self: @ContractAddress) -> felt252 {
        PedersenTrait::new(0).update_with(*self).finalize()
    }
}


impl StructHashSpanGeneric<T, +Copy<T>, +Drop<T>, +IStructHash<T>> of IStructHash<Span<T>> {
    fn get_struct_hash(self: @Span<T>) -> felt252 {
        LegacyHash::hash(0, *self)
    }
}

impl HashGenericSpanStruct<T, +Copy<T>, +Drop<T>, +IStructHash<T>,> of LegacyHash<Span<T>> {
    fn hash(mut state: felt252, mut value: Span<T>) -> felt252 {
        let list_len = value.len();
        loop {
            match value.pop_front() {
                Option::Some(item) => { state = LegacyHash::hash(state, item.get_struct_hash()); },
                Option::None => { break LegacyHash::hash(state, list_len); },
            };
        }
    }
}
