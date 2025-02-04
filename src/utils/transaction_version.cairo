use core::num::traits::Zero;
use starknet::{get_caller_address, get_tx_info};

pub const TX_V1: felt252 = 1; // INVOKE
pub const TX_V1_ESTIMATE: felt252 = 0x100000000000000000000000000000000 + 1; // 2**128 + TX_V1
const TX_V2: felt252 = 2; // DECLARE           
const TX_V2_ESTIMATE: felt252 = 0x100000000000000000000000000000000 + 2; // 2**128 + TX_V2
pub const TX_V3: felt252 = 3;
pub const TX_V3_ESTIMATE: felt252 = 0x100000000000000000000000000000000 + 3; // 2**128 + TX_V3

pub const DA_MODE_L1: u32 = 0;
const DA_MODE_L2: u32 = 1;

#[inline(always)]
pub fn assert_correct_invoke_version(tx_version: felt252) {
    assert(
        tx_version == TX_V3 || tx_version == TX_V1 || tx_version == TX_V3_ESTIMATE || tx_version == TX_V1_ESTIMATE,
        'argent/invalid-tx-version',
    )
}

#[inline(always)]
pub fn assert_correct_deploy_account_version(tx_version: felt252) {
    assert(
        tx_version == TX_V3 || tx_version == TX_V1 || tx_version == TX_V3_ESTIMATE || tx_version == TX_V1_ESTIMATE,
        'argent/invalid-deploy-account-v',
    )
}

#[inline(always)]
pub fn assert_correct_declare_version(tx_version: felt252) {
    assert(
        tx_version == TX_V3 || tx_version == TX_V2 || tx_version == TX_V3_ESTIMATE || tx_version == TX_V2_ESTIMATE,
        'argent/invalid-declare-version',
    )
}

#[inline(always)]
fn is_estimate_version(tx_version: felt252) -> bool {
    tx_version == TX_V3_ESTIMATE || tx_version == TX_V2_ESTIMATE || tx_version == TX_V1_ESTIMATE
}

#[inline(always)]
pub fn is_estimate_transaction() -> bool {
    get_caller_address().is_zero() && is_estimate_version(get_tx_info().version)
}
