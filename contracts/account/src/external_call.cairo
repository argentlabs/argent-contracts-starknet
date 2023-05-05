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

// H('StarkNetDomain(name:felt,version:felt,chainId:felt)') // TODO is this missing `verifyingContract`?
const STARKNET_DOMAIN_TYPE_HASH: felt252 =
    0x1bfc207425a47a5dfa1a50a4f5241203f50624ca5fdf5e18755765416b8e288;

#[derive(Drop)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}

// H('ExternalCalls(sender:felt,nonce:felt,min_timestamp:felt,max_timestamp:felt,calls_len:felt,calls:Call*)')
const EXTERNAL_CALLS_TYPE_HASH: felt252 = 0x0; // TODO update

#[derive(Drop, Serde)]
struct ExternalCalls {
    sender: ContractAddress,
    nonce: felt252,
    min_timestamp: u64,
    max_timestamp: u64,
    calls: Array<Call>
}

// H('ExternalCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)')
const EXTERNAL_CALL_TYPE_HASH: felt252 = 0x0; // TODO update

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
    state
}

fn hash_external_call(external_call: @Call) -> felt252 {
    let mut data_span = external_call.calldata.span();
    let mut state = perdersen(0, EXTERNAL_CALL_TYPE_HASH);
    state = perdersen(state, (*external_call.to).into());
    state = perdersen(state, *external_call.selector);
    state = perdersen(state, data_span.len().into());

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
    state = perdersen(state, call_data_state);
    state
}

fn hash_external_calls(external_calls: @ExternalCalls) -> felt252 {
    let mut calls_span = external_calls.calls.span();

    let mut state = perdersen(0, EXTERNAL_CALLS_TYPE_HASH);
    state = perdersen(state, (*external_calls.sender).into());
    state = perdersen(state, *external_calls.nonce);
    state = perdersen(state, (*external_calls.min_timestamp).into());
    state = perdersen(state, (*external_calls.max_timestamp).into());
    state = perdersen(state, calls_span.len().into());

    let mut idx = 0;
    loop {
        check_enough_gas();
        match calls_span.pop_front() {
            Option::Some(call) => {
                state = perdersen(state, hash_external_call(call));
            },
            Option::None(_) => {
                break ();
            },
        };
    };
    state
}

#[inline(always)]
fn hash_message_external_calls(external_calls: @ExternalCalls) -> felt252 {
    let domain = StarkNetDomain {
        name: 'ArgentAccount.execute_external', // TODO
        version: 1,
        chain_id: get_tx_info().unbox().chain_id,
    };
    let mut state = perdersen(0, 'StarkNet Message');
    state = perdersen(state, hash_domain(@domain));
    state = perdersen(state, get_contract_address().into());
    state = perdersen(state, hash_external_calls(external_calls));
    state
}
