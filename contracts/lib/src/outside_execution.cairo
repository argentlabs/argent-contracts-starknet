use array::{ArrayTrait, SpanTrait};
use box::BoxTrait;
use hash::pedersen;
use traits::{Into, TryInto};
use option::OptionTrait;

use starknet::{ContractAddress, ContractAddressIntoFelt252, get_tx_info, get_contract_address};

use lib::Call;

// H('StarkNetDomain(name:felt,version:felt,chainId:felt)')
const STARKNET_DOMAIN_TYPE_HASH: felt252 =
    0x1bfc207425a47a5dfa1a50a4f5241203f50624ca5fdf5e18755765416b8e288;

#[derive(Drop)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}

// H('OutsideExecution(caller:felt,nonce:felt,execute_after:felt,execute_before:felt,calls_len:felt,calls:Call*)')
const OUTSIDE_EXECUTION_TYPE_HASH: felt252 =
    0x11ff76fe3f640fa6f3d60bbd94a3b9d47141a2c96f87fdcfbeb2af1d03f7050;

#[derive(Drop, Serde)]
struct OutsideExecution {
    caller: ContractAddress,
    nonce: felt252,
    execute_after: u64,
    execute_before: u64,
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
fn hash_domain(domain: @StarkNetDomain) -> felt252 {
    let mut state = pedersen(0, STARKNET_DOMAIN_TYPE_HASH);
    state = pedersen(state, *domain.name);
    state = pedersen(state, *domain.version);
    state = pedersen(state, *domain.chain_id);
    pedersen(state, 4)
}

fn hash_outside_call(outside_call: @Call) -> felt252 {
    let mut data_span = outside_call.calldata.span();

    let mut call_data_state: felt252 = 0;
    loop {
        match data_span.pop_front() {
            Option::Some(item) => {
                call_data_state = pedersen(call_data_state, *item);
            },
            Option::None(_) => {
                break ();
            },
        };
    };
    call_data_state = pedersen(call_data_state, outside_call.calldata.len().into());

    let mut state = pedersen(0, OUTSIDE_CALL_TYPE_HASH);
    state = pedersen(state, (*outside_call.to).into());
    state = pedersen(state, *outside_call.selector);
    state = pedersen(state, outside_call.calldata.len().into());
    state = pedersen(state, call_data_state);
    pedersen(state, 5)
}

fn hash_outside_execution(outside_execution: @OutsideExecution) -> felt252 {
    let mut calls_span = outside_execution.calls.span();

    let mut outside_calls_state: felt252 = 0;
    loop {
        match calls_span.pop_front() {
            Option::Some(call) => {
                outside_calls_state = pedersen(outside_calls_state, hash_outside_call(call));
            },
            Option::None(_) => {
                break ();
            },
        };
    };
    outside_calls_state = pedersen(outside_calls_state, outside_execution.calls.len().into());

    let mut state = pedersen(0, OUTSIDE_EXECUTION_TYPE_HASH);
    state = pedersen(state, (*outside_execution.caller).into());
    state = pedersen(state, *outside_execution.nonce);
    state = pedersen(state, (*outside_execution.execute_after).into());
    state = pedersen(state, (*outside_execution.execute_before).into());
    state = pedersen(state, outside_execution.calls.len().into());
    state = pedersen(state, outside_calls_state);
    pedersen(state, 7)
}

#[inline(always)]
fn hash_outside_execution_message(outside_execution: @OutsideExecution) -> felt252 {
    let domain = StarkNetDomain {
        name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id, 
    };
    let mut state = pedersen(0, 'StarkNet Message');
    state = pedersen(state, hash_domain(@domain));
    state = pedersen(state, get_contract_address().into());
    state = pedersen(state, hash_outside_execution(outside_execution));
    pedersen(state, 4)
}
