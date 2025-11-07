use argent::offchain_message::{IStructHashRev1, StarknetDomain};
use argent::outside_execution::outside_execution_hash::{
    MAINNET_FIRST_HADES_PERMUTATION as MAINNET_FIRST_HADES_PERMUTATION_OE,
    SEPOLIA_FIRST_HADES_PERMUTATION as SEPOLIA_FIRST_HADES_PERMUTATION_OE,
};
use argent::session::session_hash::{
    MAINNET_FIRST_HADES_PERMUTATION as MAINNET_FIRST_HADES_PERMUTATION_SESSION,
    SEPOLIA_FIRST_HADES_PERMUTATION as SEPOLIA_FIRST_HADES_PERMUTATION_SESSION,
};
use core::poseidon::hades_permutation;
use snforge_std::start_cheat_chain_id_global;
use starknet::get_tx_info;


#[test]
fn session_precalculated_hash_sepolia() {
    let chain_id = get_tx_info().chain_id;
    assert_eq!(chain_id, 'SN_SEPOLIA');
    let domain = StarknetDomain { name: 'SessionAccount.session', version: '1', chain_id, revision: 1 };
    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        619758417781242245767049076918858457415551753537846667520424572098880841663,
        "Precalculated domain hash is incorrect",
    );
    let first_permutation = hades_permutation('StarkNet Message', domain_hash, 0);
    assert_eq!(first_permutation, SEPOLIA_FIRST_HADES_PERMUTATION_SESSION);
}

#[test]
fn session_precalculated_hash_mainnet() {
    let chain_id = 'SN_MAIN';
    start_cheat_chain_id_global(chain_id);
    let domain = StarknetDomain { name: 'SessionAccount.session', version: '1', chain_id, revision: 1 };

    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        2582418177524800175369952028489274182629686649307104766546635017155738899824,
        "Precalculated domain hash is incorrect",
    );
    let first_permutation = hades_permutation('StarkNet Message', domain_hash, 0);
    assert_eq!(first_permutation, MAINNET_FIRST_HADES_PERMUTATION_SESSION);
}

#[test]
fn outside_execution_precalculated_hash_sepolia() {
    let chain_id = get_tx_info().chain_id;
    assert_eq!(chain_id, 'SN_SEPOLIA');
    let domain = StarknetDomain { name: 'Account.execute_from_outside', version: 2, chain_id, revision: 1 };
    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        1051717892762963823896080394520401037226570779498494081884365074830163874271,
        "Precalculated domain hash is incorrect",
    );
    let first_permutation = hades_permutation('StarkNet Message', domain_hash, 0);
    assert_eq!(first_permutation, SEPOLIA_FIRST_HADES_PERMUTATION_OE);
}

#[test]
fn outside_execution_precalculated_hash_mainnet() {
    let chain_id = 'SN_MAIN';
    start_cheat_chain_id_global(chain_id);
    let domain = StarknetDomain { name: 'Account.execute_from_outside', version: 2, chain_id, revision: 1 };
    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        270892730805027368931547576938878097625671597714003823052343939644536693420,
        "Precalculated domain hash is incorrect",
    );
    let first_permutation = hades_permutation('StarkNet Message', domain_hash, 0);
    assert_eq!(first_permutation, MAINNET_FIRST_HADES_PERMUTATION_OE);
}
