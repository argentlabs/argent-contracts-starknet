use argent::signer::signer_signature::{Signer, StarknetSignature, IntoGuid, SignerIntoGuid, SignerSignature};
use poseidon::{poseidon_hash_span};
use starknet::account::Call;
use starknet::{get_tx_info, get_contract_address, ContractAddress};

#[starknet::interface]
trait ISessionable<TContractState> {
    /// @notice This method allows user to revoke a session based on its hash
    /// @param session_hash Hash of the session token
    fn revoke_session(ref self: TContractState, session_hash: felt252);

    /// @notice View method to see if a session is revoked, returns a boolean 
    fn is_session_revoked(self: @TContractState, session_hash: felt252) -> bool;
}

#[derive(Drop, Serde, Copy)]
struct Session {
    expires_at: u64,
    allowed_methods_root: felt252,
    metadata_hash: felt252,
    session_key_guid: felt252,
}

#[derive(Drop, Serde, Copy)]
struct SessionToken {
    session: Session,
    session_authorisation: Span<felt252>,
    session_signature: SignerSignature,
    guardian_signature: SignerSignature,
    proofs: Span<Span<felt252>>,
}

#[derive(Hash, Drop, Copy)]
struct StarknetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
    revision: felt252,
}


const STARKNET_DOMAIN_TYPE_HASH: felt252 =
    selector!(
        "\"StarknetDomain\"(\"name\":\"shortstring\",\"version\":\"shortstring\",\"chainId\":\"shortstring\",\"revision\":\"shortstring\")"
    );
const SESSION_TYPE_HASH: felt252 =
    selector!(
        "\"Session\"(\"Expires At\":\"timestamp\",\"Allowed Methods\":\"merkletree\",\"Metadata\":\"string\",\"Session Key\":\"felt\")"
    );
const ALLOWED_METHOD_HASH: felt252 =
    selector!("\"Allowed Method\"(\"Contract Address\":\"ContractAddress\",\"selector\":\"selector\")");


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
        poseidon_hash_span(array![ALLOWED_METHOD_HASH, (*self.to).into(), *self.selector].span())
    }
}


impl StructHashSession of IStructHash<Session> {
    fn get_struct_hash(self: @Session) -> felt252 {
        poseidon_hash_span(
            array![
                SESSION_TYPE_HASH,
                (*self.expires_at).into(),
                *self.allowed_methods_root,
                *self.metadata_hash,
                *self.session_key_guid
            ]
                .span()
        )
    }
}


impl StructHashStarknetDomain of IStructHash<StarknetDomain> {
    fn get_struct_hash(self: @StarknetDomain) -> felt252 {
        poseidon_hash_span(
            array![STARKNET_DOMAIN_TYPE_HASH, *self.name, *self.version, *self.chain_id, *self.revision].span()
        )
    }
}

impl OffchainMessageHashSession of IOffchainMessageHash<Session> {
    fn get_message_hash(self: @Session) -> felt252 {
        let domain = StarknetDomain {
            name: 'SessionAccount.session', version: 1, chain_id: get_tx_info().unbox().chain_id, revision: 1,
        };
        poseidon_hash_span(
            array!['StarkNet Message', domain.get_struct_hash(), get_contract_address().into(), self.get_struct_hash()]
                .span()
        )
    }
}
