use starknet::{SyscallResultTrait};

const TX_INVOKE_V1: felt252 = 1;
const TX_INVOKE_V1_ESTIMATE: felt252 = 0x100000000000000000000000000000001; // 2**128 + TX_INVOKE_V1
const TX_INVOKE_V2: felt252 = 2;
const TX_INVOKE_V2_ESTIMATE: felt252 = 0x100000000000000000000000000000002; // 2**128 + TX_INVOKE_V2
const TX_V3: felt252 = 3;
const TX_V3_ESTIMATE: felt252 = 0x100000000000000000000000000000003; // 2**128 + TX_V3


#[inline(always)]
fn assert_correct_invoke_version(tx_version: felt252) {
    assert(
        tx_version == TX_V3
            || tx_version == TX_INVOKE_V1
            || tx_version == TX_V3_ESTIMATE
            || tx_version == TX_INVOKE_V1_ESTIMATE,
        'argent/invalid-tx-version'
    )
}

#[inline(always)]
fn assert_correct_declare_version(tx_version: felt252) {
    assert(
        tx_version == TX_V3
            || tx_version == TX_INVOKE_V2
            || tx_version == TX_V3_ESTIMATE
            || tx_version == TX_INVOKE_V2_ESTIMATE,
        'argent/invalid-declare-version'
    )
}

#[inline(always)]
fn assert_no_unsupported_v3_fields() {
    let tx_info = get_tx_info().unbox();
    assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
// more fields?
}


#[inline(always)]
fn get_execution_info() -> Box<starknet::info::v2::ExecutionInfo> {
    starknet::syscalls::get_execution_info_v2_syscall().unwrap_syscall()
}

#[inline(always)]
fn get_tx_info() -> Box<starknet::info::v2::TxInfo> {
    get_execution_info().unbox().tx_info
}
// #[inline(always)]
// fn get_execution_info() -> Box<starknet::info::ExecutionInfo> {
//     starknet::syscalls::get_execution_info_syscall().unwrap_syscall()
// }

// #[inline(always)]
// fn get_tx_info() -> Box<starknet::info::TxInfo> {
//     get_execution_info().unbox().tx_info
// }

