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

// H('OutsideExecution(caller:felt,nonce:felt,min_timestamp:felt,max_timestamp:felt,calls_len:felt,calls:Call*)')
const OUTSIDE_EXECUTION_TYPE_HASH: felt252 =
    0x129325d420651cb60aa9b3aee69dd93076b0a1e37970032cd533cc29a2e4f99;

#[derive(Drop, Serde)]
struct OutsideExecution {
    caller: ContractAddress,
    nonce: felt252,
    min_timestamp: u64,
    max_timestamp: u64,
    calls: Array<Call>
}

// H('OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)')
const OUTSIDE_CALL_TYPE_HASH: felt252 =
    0xf00de1fccbb286f9a020ba8821ee936b1deea42a5c485c11ccdc82c8bebb3a;

#[derive(Drop, Serde)]
struct OutsideCall {
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

fn hash_outside_call(outside_call: @Call) -> felt252 {
    let mut data_span = outside_call.calldata.span();

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
    call_data_state = perdersen(call_data_state, outside_call.calldata.len().into());

    let mut state = perdersen(0, OUTSIDE_CALL_TYPE_HASH);
    state = perdersen(state, (*outside_call.to).into());
    state = perdersen(state, *outside_call.selector);
    state = perdersen(state, outside_call.calldata.len().into());
    state = perdersen(state, call_data_state);
    perdersen(state, 5)
}

fn hash_outside_execution(outside_execution: @OutsideExecution) -> felt252 {
    let mut calls_span = outside_execution.calls.span();

    let mut outside_calls_state: felt252 = 0;
    loop {
        check_enough_gas();
        match calls_span.pop_front() {
            Option::Some(call) => {
                outside_calls_state = perdersen(outside_calls_state, hash_outside_call(call));
            },
            Option::None(_) => {
                break ();
            },
        };
    };
    outside_calls_state = perdersen(outside_calls_state, outside_execution.calls.len().into());

    let mut state = perdersen(0, OUTSIDE_EXECUTION_TYPE_HASH);
    state = perdersen(state, (*outside_execution.caller).into());
    state = perdersen(state, *outside_execution.nonce);
    state = perdersen(state, (*outside_execution.min_timestamp).into());
    state = perdersen(state, (*outside_execution.max_timestamp).into());
    state = perdersen(state, outside_execution.calls.len().into());
    state = perdersen(state, outside_calls_state);
    perdersen(state, 7)
}

#[inline(always)]
fn hash_outside_execution_message(outside_execution: @OutsideExecution) -> felt252 {
    let domain = StarkNetDomain {
        name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id, 
    };
    let mut state = perdersen(0, 'StarkNet Message');
    state = perdersen(state, hash_domain(@domain));
    state = perdersen(state, get_contract_address().into());
    state = perdersen(state, hash_outside_execution(outside_execution));
    perdersen(state, 4)
}
