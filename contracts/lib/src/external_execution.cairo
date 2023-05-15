use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use lib::Call;
use starknet::ContractAddress;
use starknet::ContractAddressIntoFelt252;
use lib::check_enough_gas;
use array::ArrayTrait;
use array::SpanTrait;
use starknet::get_tx_info;
use box::BoxTrait;
use starknet::get_contract_address;

// H('StarkNetDomain(name:felt,version:felt,chainId:felt)')
const STARKNET_DOMAIN_TYPE_HASH: felt252 =
    0x1bfc207425a47a5dfa1a50a4f5241203f50624ca5fdf5e18755765416b8e288;

#[derive(Drop)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}

// H('ExternalExecution(sender:felt,min_timestamp:felt,max_timestamp:felt,calls_len:felt,calls:Call*)')
const EXTERNAL_EXECUTION_TYPE_HASH: felt252 =
    0x1a33dfa608bfc0d078004fbdb7f8323acd5d9236aed810c7927f8f50803d93b;

#[derive(Drop, Serde)]
struct ExternalExecution {
    sender: ContractAddress,
    min_timestamp: u64,
    max_timestamp: u64,
    calls: Array<Call>
}

// H('ExternalCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)')
const EXTERNAL_CALL_TYPE_HASH: felt252 =
    0x1bc515e812859cc94d04ef18a634bf57efd0b3d1cb66c6011fb433e1ae44a7;

#[derive(Drop, Serde)]
struct ExternalCall {
    to: ContractAddress,
    selector: felt252,
    calldata: Array<felt252>,
}

#[inline(always)]
fn perdersen(state: felt252, another: felt252) -> felt252 {
    hash::LegacyHashFelt252::hash(state, another)
}

#[inline(always)]
fn hash_domain(domain: @StarkNetDomain) -> felt252 {
    let mut state = perdersen(0, STARKNET_DOMAIN_TYPE_HASH);
    state = perdersen(state, *domain.name);
    state = perdersen(state, *domain.version);
    state = perdersen(state, *domain.chain_id);
    perdersen(state, 4)
}

fn hash_external_call(external_call: @Call) -> felt252 {
    let mut data_span = external_call.calldata.span();

    let mut call_data_state: felt252 = 0;
    loop {
        check_enough_gas();
        match data_span.pop_front() {
            Option::Some(item) => {
                call_data_state = perdersen(call_data_state, *item);
            },
            Option::None(_) => {
                break ();
            },
        };
    };
    call_data_state = perdersen(call_data_state, external_call.calldata.len().into());

    let mut state = perdersen(0, EXTERNAL_CALL_TYPE_HASH);
    state = perdersen(state, (*external_call.to).into());
    state = perdersen(state, *external_call.selector);
    state = perdersen(state, external_call.calldata.len().into());
    state = perdersen(state, call_data_state);
    perdersen(state, 5)
}

fn hash_external_execution(external_calls: @ExternalExecution) -> felt252 {
    let mut calls_span = external_calls.calls.span();

    let mut external_calls_state: felt252 = 0;
    loop {
        check_enough_gas();
        match calls_span.pop_front() {
            Option::Some(call) => {
                external_calls_state = perdersen(external_calls_state, hash_external_call(call));
            },
            Option::None(_) => {
                break ();
            },
        };
    };
    external_calls_state = perdersen(external_calls_state, external_calls.calls.len().into());

    let mut state = perdersen(0, EXTERNAL_EXECUTION_TYPE_HASH);
    state = perdersen(state, (*external_calls.sender).into());
    state = perdersen(state, (*external_calls.min_timestamp).into());
    state = perdersen(state, (*external_calls.max_timestamp).into());
    state = perdersen(state, external_calls.calls.len().into());
    state = perdersen(state, external_calls_state);
    perdersen(state, 6)
}

#[inline(always)]
fn hash_external_execution_message(external_execution: @ExternalExecution) -> felt252 {
    let domain = StarkNetDomain {
        name: 'ArgentAccount.execute_external',
        version: 1,
        chain_id: get_tx_info().unbox().chain_id,
    };
    let mut state = perdersen(0, 'StarkNet Message');
    state = perdersen(state, hash_domain(@domain));
    state = perdersen(state, get_contract_address().into());
    state = perdersen(state, hash_external_execution(external_execution));
    perdersen(state, 4)
}
