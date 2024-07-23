use argent::offchain_message::interface::{IStructHashRev1, StarknetDomain};
use argent::outside_execution::outside_execution_hash::{
    MAINNET_FIRST_HADES_PERMUTATION as MAINNET_FIRST_HADES_PERMUTATION_OE,
    SEPOLIA_FIRST_HADES_PERMUTATION as SEPOLIA_FIRST_HADES_PERMUTATION_OE
};
use argent::session::session_hash::{
    MAINNET_FIRST_HADES_PERMUTATION as MAINNET_FIRST_HADES_PERMUTATION_SESSION,
    SEPOLIA_FIRST_HADES_PERMUTATION as SEPOLIA_FIRST_HADES_PERMUTATION_SESSION
};
use poseidon::hades_permutation;
use starknet::get_tx_info;

use super::setup::utils::set_chain_id_foundry;


#[test]
fn session_precalculated_hash_sepolia() {
    let domain = StarknetDomain {
        name: 'SessionAccount.session', version: '1', chain_id: get_tx_info().unbox().chain_id, revision: 1,
    };
    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        619758417781242245767049076918858457415551753537846667520424572098880841663,
        "Precalculated domain hash is incorrect"
    );
    let (ch0, ch1, ch2) = hades_permutation('StarkNet Message', domain_hash, 0);
    let (pch0, pch1, pch2) = SEPOLIA_FIRST_HADES_PERMUTATION_SESSION;
    assert_eq!(ch0, pch0, "Precalculated hash is incorrect");
    assert_eq!(ch1, pch1, "Precalculated hash is incorrect");
    assert_eq!(ch2, pch2, "Precalculated hash is incorrect");
}

#[test]
fn session_precalculated_hash_mainnet() {
    set_chain_id_foundry('SN_MAIN');
    let domain = StarknetDomain {
        name: 'SessionAccount.session', version: '1', chain_id: get_tx_info().unbox().chain_id, revision: 1,
    };

    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        2582418177524800175369952028489274182629686649307104766546635017155738899824,
        "Precalculated domain hash is incorrect"
    );
    let (ch0, ch1, ch2) = hades_permutation('StarkNet Message', domain_hash, 0);
    let (pch0, pch1, pch2) = MAINNET_FIRST_HADES_PERMUTATION_SESSION;
    assert_eq!(ch0, pch0, "Precalculated hash is incorrect");
    assert_eq!(ch1, pch1, "Precalculated hash is incorrect");
    assert_eq!(ch2, pch2, "Precalculated hash is incorrect");
}

#[test]
fn outside_execution_precalculated_hash_sepolia() {
    let domain = StarknetDomain {
        name: 'Account.execute_from_outside', version: 2, chain_id: get_tx_info().unbox().chain_id, revision: 1,
    };
    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        1051717892762963823896080394520401037226570779498494081884365074830163874271,
        "Precalculated domain hash is incorrect"
    );
    let (ch0, ch1, ch2) = hades_permutation('StarkNet Message', domain_hash, 0);
    let (pch0, pch1, pch2) = SEPOLIA_FIRST_HADES_PERMUTATION_OE;
    assert_eq!(ch0, pch0, "Precalculated hash is incorrect");
    assert_eq!(ch1, pch1, "Precalculated hash is incorrect");
    assert_eq!(ch2, pch2, "Precalculated hash is incorrect");
}

#[test]
fn outside_execution_precalculated_hash_mainnet() {
    set_chain_id_foundry('SN_MAIN');
    let domain = StarknetDomain {
        name: 'Account.execute_from_outside', version: 2, chain_id: get_tx_info().unbox().chain_id, revision: 1,
    };
    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        270892730805027368931547576938878097625671597714003823052343939644536693420,
        "Precalculated domain hash is incorrect"
    );
    let (ch0, ch1, ch2) = hades_permutation('StarkNet Message', domain_hash, 0);
    let (pch0, pch1, pch2) = MAINNET_FIRST_HADES_PERMUTATION_OE;
    assert_eq!(ch0, pch0, "Precalculated hash is incorrect");
    assert_eq!(ch1, pch1, "Precalculated hash is incorrect");
    assert_eq!(ch2, pch2, "Precalculated hash is incorrect");
}
