use argent::offchain_message::{
    interface::{StarknetDomain, StructHashStarknetDomain, IMerkleLeafHash, IStructHashRev1, IOffChainMessageHashRev1,},
    precalculated_hashing::get_message_hash_rev_1_with_precalc
};
use argent::session::interface::Session;
use hash::{HashStateExTrait, HashStateTrait};
use poseidon::{hades_permutation, poseidon_hash_span, HashState};
use starknet::{get_contract_address, get_tx_info, account::Call};


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
        // WARNING! Please do not use this starknet domain as it is wrong.
        // Version and Revision should be shortstring '1' not felt 1
        // This is due to a mistake made in the Braavos contracts and has been copied for compatibility
        let chain_id = get_tx_info().unbox().chain_id;
        if chain_id == 'SN_MAIN' {
            let mainnet_first_hades_permutation = (
                2323134905843710400277850554467420438836802451436694979291226432262210349922,
                497047802536209445013847976375993952138881488253153206740640135894961444223,
                1534648249535688540587269261500462862519297145299981583675973457661163002808
            );
            return get_message_hash_rev_1_with_precalc(mainnet_first_hades_permutation, *self);
        }
        if chain_id == 'SN_GOERLI' {
            let goerli_first_hades_permutation = (
                66935669433055122830338184180135473587363615299602357034397441854497537432,
                3129201308487698509211263622535430894718798011618046231006704155132513876661,
                1564676662968736057938598045533672220702488601100673957348600464129471843386
            );
            return get_message_hash_rev_1_with_precalc(goerli_first_hades_permutation, *self);
        }
        let domain = StarknetDomain { name: 'SessionAccount.session', version: 1, chain_id, revision: 1, };
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
