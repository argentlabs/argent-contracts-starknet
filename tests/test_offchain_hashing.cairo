use argent::offchain_message::{
    interface::{IStructHashRev1, StarknetDomain}, precalculated_hashing::{get_message_hash_rev_1_with_precalc}
};
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
        name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id, revision: 1,
    };
    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        1846363217105511744772004537093892420835749696406530113218718373305116005176,
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
        name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id, revision: 1,
    };
    let domain_hash = domain.get_struct_hash_rev_1();
    assert_eq!(
        domain_hash,
        33781215245670134228908646522746461659628127223637352174002236121260749013,
        "Precalculated domain hash is incorrect"
    );
    let (ch0, ch1, ch2) = hades_permutation('StarkNet Message', domain_hash, 0);
    let (pch0, pch1, pch2) = MAINNET_FIRST_HADES_PERMUTATION_OE;
    assert_eq!(ch0, pch0, "Precalculated hash is incorrect");
    assert_eq!(ch1, pch1, "Precalculated hash is incorrect");
    assert_eq!(ch2, pch2, "Precalculated hash is incorrect");
}
