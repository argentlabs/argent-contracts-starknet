use argent::offchain_message::interface::{
    StarknetDomain, StructHashStarknetDomain, IMerkleLeafHash, IStructHashRev1, IOffChainMessageHashRev1
};
use argent::session::interface::Session;
use argent::utils::hashing::get_message_hash_rev_1_with_precalc;
use hash::{HashStateExTrait, HashStateTrait};
use poseidon::{hades_permutation, poseidon_hash_span, HashState};
use starknet::{get_contract_address, get_tx_info, account::Call};


const MAINNET_FIRST_HADES_PERMUTATION: (felt252, felt252, felt252) =
    (
        3159357451750963173197764487250193801745009044296318704413979805593222351753,
        2856607116111318915813829371903536205200021468882518469573183227809900863246,
        2405333218043798385503929428387279699579326006043041470088260529024671365157
    );

const SEPOLIA_FIRST_HADES_PERMUTATION: (felt252, felt252, felt252) =
    (
        691798498452391354097240300284680479233893583850648846821812933705410085810,
        317062340895242311773051982041708757540909251525159061717012359096590796798,
        517893314125397876808992724850240644188517690767234330219248407741294215037
    );


const SESSION_TYPE_HASH_REV_1: felt252 =
    selector!(
        "\"Session\"(\"Expires At\":\"timestamp\",\"Allowed Methods\":\"merkletree\",\"Metadata\":\"string\",\"Session Key\":\"felt\")"
    );

const ALLOWED_METHOD_HASH_REV_1: felt252 =
    selector!("\"Allowed Method\"(\"Contract Address\":\"ContractAddress\",\"selector\":\"selector\")");

impl MerkleLeafHash of IMerkleLeafHash<Call> {
    fn get_merkle_leaf(self: @Call) -> felt252 {
        poseidon_hash_span(array![ALLOWED_METHOD_HASH_REV_1, (*self.to).into(), *self.selector].span())
    }
}

impl StructHashSession of IStructHashRev1<Session> {
    fn get_struct_hash_rev_1(self: @Session) -> felt252 {
        let self = *self;
        poseidon_hash_span(
            array![
                SESSION_TYPE_HASH_REV_1,
                self.expires_at.into(),
                self.allowed_methods_root,
                self.metadata_hash,
                self.session_key_guid
            ]
                .span()
        )
    }
}

impl OffChainMessageHashSessionRev1 of IOffChainMessageHashRev1<Session> {
    fn get_message_hash_rev_1(self: @Session) -> felt252 {
        let chain_id = get_tx_info().chain_id;
        if chain_id == 'SN_MAIN' {
            return get_message_hash_rev_1_with_precalc(MAINNET_FIRST_HADES_PERMUTATION, *self);
        }
        if chain_id == 'SN_SEPOLIA' {
            return get_message_hash_rev_1_with_precalc(SEPOLIA_FIRST_HADES_PERMUTATION, *self);
        }
        let domain = StarknetDomain { name: 'SessionAccount.session', version: '1', chain_id, revision: 1, };
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
