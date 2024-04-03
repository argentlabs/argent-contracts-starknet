use argent::offchain_message::interface::{
    StarknetDomain, StructHashStarknetDomain, IMerkleLeafHash, IStructHashRev1, IOffChainMessageHashRev1
};
use argent::session::interface::Session;
use poseidon::{hades_permutation, poseidon_hash_span, HashState};
use starknet::{get_contract_address, get_tx_info, account::Call};
use hash::{HashStateExTrait, HashStateTrait};


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
        let domain = StarknetDomain {
            name: 'SessionAccount.session', version: 1, chain_id: get_tx_info().unbox().chain_id, revision: 1,
        };
        // 675582295603192327528831240503702820896706487235401654583087856516636529744
        // poseidon_hash_span(
        //     array![
        //         'StarkNet Message',
        //         675582295603192327528831240503702820896706487235401654583087856516636529744,
        //         get_contract_address().into(),
        //         self.get_struct_hash_rev_1()
        //     ]
        //         .span()
        // )

    // let (fs0, fs1, fs2) = hades_permutation(66935669433055122830338184180135473587363615299602357034397441854497537432 +  get_contract_address().into(), 3129201308487698509211263622535430894718798011618046231006704155132513876661 + self.get_struct_hash_rev_1(), 1564676662968736057938598045533672220702488601100673957348600464129471843386);
    // let final = HashState { s0: fs0, s1:fs1, s2:fs2, odd: false }.finalize();
    // final

//     // domain hash for mainnet
// const mainnet_domain_hash = 675582295603192327528831240503702820896706487235401654583087856516636529744;
// // result of hades_permutation('StarkNet Message', mainnet_domain_hash, 0);
// const mainnet_first_hades_permutation = (66935669433055122830338184180135473587363615299602357034397441854497537432, 3129201308487698509211263622535430894718798011618046231006704155132513876661, 1564676662968736057938598045533672220702488601100673957348600464129471843386);

// if mainet {
//     let (mfhp0, mfhp1, mfhp2) = mainnet_first_hades_permutation;

//     let (final_hash, _, _) = hades_permutation(
//         mfhp0 +  get_contract_address().into(), 
//         mfhp1 + self.get_struct_hash_rev_1(), 
//         mfhp2
//     );
//     final_hash
// } else {
//         poseidon_hash_span(
//             array![
//                 'StarkNet Message',
//                 domain.get_struct_hash_rev_1(),
//                 get_contract_address().into(),
//                 self.get_struct_hash_rev_1()
//             ]
//                 .span()
//         )
// }
//     }
}
