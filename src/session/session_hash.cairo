use argent::offchain_message::interface::{
    StarknetDomain, StructHashStarknetDomain, IMerkleLeafHash, IStructHashRev1, IOffChainMessageHashRev1
};
use argent::session::interface::Session;
use poseidon::poseidon_hash_span;
use starknet::{get_contract_address, get_tx_info, account::Call};

const SESSION_TYPE_HASH: felt252 =
    selector!(
        "\"Session\"(\"Expires At\":\"timestamp\",\"Allowed Methods\":\"merkletree\",\"Metadata\":\"string\",\"Session Key\":\"felt\")"
    );
const ALLOWED_METHOD_HASH: felt252 =
    selector!("\"Allowed Method\"(\"Contract Address\":\"ContractAddress\",\"selector\":\"selector\")");


impl MerkleLeafHash of IMerkleLeafHash<Call> {
    fn get_merkle_leaf(self: @Call) -> felt252 {
        poseidon_hash_span(array![ALLOWED_METHOD_HASH, (*self.to).into(), *self.selector].span())
    }
}

impl StructHashSession of IStructHashRev1<Session> {
    fn get_struct_hash_rev_1(self: @Session) -> felt252 {
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

impl OffChainMessageHashSessionRev1 of IOffChainMessageHashRev1<Session> {
    fn get_message_hash_rev_1(self: @Session) -> felt252 {
        let domain = StarknetDomain {
            name: 'SessionAccount.session', version: 1, chain_id: get_tx_info().unbox().chain_id, revision: 1,
        };
        poseidon_hash_span(
            array![
                'StarkNet Message',
                domain.get_struct_hash_rev_1(),
                get_contract_address().into(),
                self.get_struct_hash_rev_1()
            ]
                .span()
        )
    }
}
