use argent::offchain_message::interface::{
    StarkNetDomain, StarknetDomain, StructHashStarkNetDomain, IOffChainMessageHashRev0, IStructHashRev0,
    IOffChainMessageHashRev1, IStructHashRev1,
};
use argent::outside_execution::interface::{OutsideExecution};
use hash::{HashStateTrait, HashStateExTrait};
use pedersen::PedersenTrait;
use poseidon::poseidon_hash_span;
use starknet::{get_tx_info, get_contract_address, account::Call};

const OUTSIDE_CALL_TYPE_HASH: felt252 =
    selector!("OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)");


const OUTSIDE_EXECUTION_TYPE_HASH_REV_0: felt252 =
    selector!(
        "OutsideExecution(caller:felt,nonce:felt,execute_after:felt,execute_before:felt,calls_len:felt,calls:OutsideCall*)OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)"
    );


const OUTSIDE_EXECUTION_TYPE_HASH_REV_1: felt252 =
    selector!(
        "\"OutsideExecution\"(\"Caller\":\"ContractAddress\",\"Nonce\":\"felt\",\"Execute After\":\"u128\",\"Execute Before\":\"u128\",\"Calls\":\"Call*\")\"Call\"(\"To\":\"ContractAddress\",\"Selector\":\"selector\",\"Calldata\":\"felt*\")"
    );

const CALL_TYPE_HASH: felt252 =
    selector!("\"Call\"(\"To\":\"ContractAddress\",\"Selector\":\"selector\",\"Calldata\":\"felt*\")");


impl StructHashOutsideExecutionRev0 of IStructHashRev0<OutsideExecution> {
    fn get_struct_hash_rev_0(self: @OutsideExecution) -> felt252 {
        let mut state = PedersenTrait::new(0);
        let mut calls_span = *self.calls;
        let calls_len = (*self.calls).len().into();
        let calls_hash = loop {
            match calls_span.pop_front() {
                Option::Some(call) => state = state.update((call.get_struct_hash_rev_0())),
                Option::None => { break state.update(calls_len).finalize(); },
            }
        };

        PedersenTrait::new(0)
            .update_with(OUTSIDE_EXECUTION_TYPE_HASH_REV_0)
            .update_with(*self.caller)
            .update_with(*self.nonce)
            .update_with(*self.execute_after)
            .update_with(*self.execute_before)
            .update_with(calls_len)
            .update_with(calls_hash)
            .update_with(7)
            .finalize()
    }
}

impl StructHashCallRev0 of IStructHashRev0<Call> {
    fn get_struct_hash_rev_0(self: @Call) -> felt252 {
        let mut state = PedersenTrait::new(0);
        let mut calldata_span = *self.calldata;
        let calldata_len = calldata_span.len().into();
        let calldata_hash = loop {
            match calldata_span.pop_front() {
                Option::Some(item) => state = state.update(*item),
                Option::None => { break state.update(calldata_len).finalize(); },
            }
        };

        PedersenTrait::new(0)
            .update_with(OUTSIDE_CALL_TYPE_HASH)
            .update_with(*self.to)
            .update_with(*self.selector)
            .update_with(calldata_len)
            .update_with(calldata_hash)
            .update_with(5)
            .finalize()
    }
}

impl OffChainMessageOutsideExecutionRev0 of IOffChainMessageHashRev0<OutsideExecution> {
    fn get_message_hash_rev_0(self: @OutsideExecution) -> felt252 {
        let domain = StarkNetDomain {
            name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id,
        };

        PedersenTrait::new(0)
            .update_with('StarkNet Message')
            .update_with(domain.get_struct_hash_rev_0())
            .update_with(get_contract_address())
            .update_with((*self).get_struct_hash_rev_0())
            .update(4)
            .finalize()
    }
}

impl StructHashCallRev1 of IStructHashRev1<Call> {
    fn get_struct_hash_rev_1(self: @Call) -> felt252 {
        poseidon_hash_span(
            array![CALL_TYPE_HASH, (*self.to).into(), *self.selector, poseidon_hash_span(*self.calldata)].span()
        )
    }
}


impl StructHashOutsideExecutionRev1 of IStructHashRev1<OutsideExecution> {
    fn get_struct_hash_rev_1(self: @OutsideExecution) -> felt252 {
        let mut calls_span = *self.calls;
        let mut hashed_calls = array![];

        loop {
            match calls_span.pop_front() {
                Option::Some(call) => { hashed_calls.append(call.get_struct_hash_rev_1()); },
                Option::None(_) => { break; },
            };
        };

        poseidon_hash_span(
            array![
                OUTSIDE_EXECUTION_TYPE_HASH_REV_1,
                (*self.caller).into(),
                *self.nonce,
                (*self.execute_after).into(),
                (*self.execute_before).into(),
                poseidon_hash_span(hashed_calls.span()),
            ]
                .span()
        )
    }
}


impl OffChainMessageOutsideExecutionRev1 of IOffChainMessageHashRev1<OutsideExecution> {
    fn get_message_hash_rev_1(self: @OutsideExecution) -> felt252 {
        let domain = StarknetDomain {
            name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id, revision: 1
        };
        poseidon_hash_span(
            array![
                'StarkNet Message',
                domain.get_struct_hash_rev_1(),
                get_contract_address().into(),
                (*self).get_struct_hash_rev_1(),
            ]
                .span()
        )
    }
}

