use core::traits::Into;
use hash::{HashStateExTrait, HashStateTrait};
use poseidon::{PoseidonTrait};
use starknet::account::Call;
use starknet::{get_tx_info, get_contract_address, ContractAddress};


#[derive(Drop, Serde, Copy)]
struct StarknetSignature {
    r: felt252,
    s: felt252,
}

#[derive(Hash, Drop, Serde, Copy)]
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
struct StarknetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
    revision: felt252,
}

//.update_with these once SNIP-12 is merged (i.e. use StarknetDomain)
const STARKNET_DOMAIN_TYPE_HASH: felt252 = selector!("StarknetDomain(name:shortstring,version:shortstring,chainId:shortstring,revision:shortstring)");
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
        let mut state = PoseidonTrait::new();
        state = state.update_with(ALLOWED_METHOD_HASH);
        state = state.update_with(*self.to);
        state = state.update_with(*self.selector);
        state = state.update_with(3);
        state.finalize()
    }
}


impl StructHashSession of IStructHash<Session> {
    fn get_struct_hash(self: @Session) -> felt252 {
        let mut state = PoseidonTrait::new();
        state = state.update_with(SESSION_TYPE_HASH);
        state = state.update_with(*self);
        state = state.update_with(5);
        state.finalize()
    }
}


impl StructHashStarknetDomain of IStructHash<StarknetDomain> {
    fn get_struct_hash(self: @StarknetDomain) -> felt252 {
        let mut state = PoseidonTrait::new();
        state = state.update_with(STARKNET_DOMAIN_TYPE_HASH);
        state = state.update_with(*self);
        state = state.update_with(5);
        state.finalize()
    }
}

impl OffchainMessageHashSession of IOffchainMessageHash<Session> {
    fn get_message_hash(self: @Session) -> felt252 {
        let domain = StarknetDomain {
            name: 'SessionAccount.session', version: 1, chain_id: get_tx_info().unbox().chain_id, revision: 1,
        };
        let mut state = PoseidonTrait::new();
        state = state.update_with('StarkNet Message');
        state = state.update_with(domain.get_struct_hash());
        state = state.update_with(get_contract_address());
        state = state.update_with(self.get_struct_hash());
        state = state.update_with(4);
        state.finalize()
    }
}
