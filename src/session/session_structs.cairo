use box::BoxTrait;
use hash::{HashStateTrait, HashStateExTrait, LegacyHash};
use pedersen::PedersenTrait;
use starknet::account::Call;
use starknet::{get_tx_info, get_contract_address, ContractAddress};

#[derive(Drop, Serde, Copy)]
struct TokenLimit {
    contract_address: ContractAddress,
    amount: u256,
}

#[derive(Drop, Serde, Copy)]
struct Session {
    session_key: felt252,
    expires_at: u64,
    allowed_methods_root: felt252,
    max_fee_usage: u128,
    token_limits: Span<TokenLimit>,
    nft_contracts: Span<ContractAddress>,
}

#[derive(Drop, Serde, Copy)]
struct SessionToken {
    session: Session,
    session_signature: Span<felt252>,
    owner_signature: Span<felt252>,
    backend_signature: Span<felt252>,
    proofs: Span<Span<felt252>>,
}

#[derive(Hash, Drop, Copy)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}


const STARKNET_DOMAIN_TYPE_HASH: felt252 = selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");
const SESSION_TYPE_HASH: felt252 =
    selector!(
        "Session(Session Key:felt,Expires At:felt,Allowed Methods:merkletree,max_fee_usage:felt,token_limits:TokenLimit*,nft_contracts:felt*)TokenLimit(contract_address:felt,amount:u256)u256(low:felt,high:felt)"
    );
const TOKEN_LIMIT_HASH: felt252 = selector!("TokenLimit(contract_address:felt,amount:u256)u256(low:felt,high:felt)");
const U256_TYPE_HASH: felt252 = selector!("u256(low:felt,high:felt)");
const ALLOWED_METHOD_HASH: felt252 = selector!("Allowed Method(Contract Address:felt,selector:selector)");


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
        state = state.update_with(*self.session_key);
        state = state.update_with(*self.expires_at);
        state = state.update_with(*self.allowed_methods_root);
        state = state.update_with(*self.max_fee_usage);
        state = state.update_with((*self).token_limits.get_struct_hash());
        state = state.update_with((*self).nft_contracts.get_struct_hash());
        state = state.update_with(7);
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


impl StructHashU256 of IStructHash<u256> {
    fn get_struct_hash(self: @u256) -> felt252 {
        let mut state = PedersenTrait::new(0);
        state = state.update_with(U256_TYPE_HASH);
        state = state.update_with(*self);
        state = state.update_with(3);
        state.finalize()
    }
}

impl StructHashSpanContract of IStructHash<ContractAddress> {
    fn get_struct_hash(self: @ContractAddress) -> felt252 {
        let mut state = PedersenTrait::new(0);
        state.update_with(*self);
        state.finalize()
    }
}


impl StructHashTokenLimit of IStructHash<TokenLimit> {
    fn get_struct_hash(self: @TokenLimit) -> felt252 {
        let mut state = PedersenTrait::new(0);
        state = state.update_with(TOKEN_LIMIT_HASH);
        state = state.update_with(*self.contract_address);
        state = state.update_with((*self).amount.get_struct_hash());
        state = state.update_with(3);
        state.finalize()
    }
}


impl StructHashSpanGeneric<
    T, impl TCopy: Copy<T>, impl TDrop: Drop<T>, impl THash: IStructHash<T>
> of IStructHash<Span<T>> {
    fn get_struct_hash(self: @Span<T>) -> felt252 {
        let mut state = LegacyHash::hash(0, *self);
        state
    }
}

impl HashGenericSpanStruct<
    T, impl TCopy: Copy<T>, impl TDrop: Drop<T>, impl THash: IStructHash<T>,
> of LegacyHash<Span<T>> {
    fn hash(mut state: felt252, mut value: Span<T>) -> felt252 {
        let list_len = value.len();
        loop {
            match value.pop_front() {
                Option::Some(item) => { state = LegacyHash::hash(state, (*item).get_struct_hash()); },
                Option::None(_) => {
                    state = LegacyHash::hash(state, list_len);
                    break state;
                },
            };
        }
    }
}
