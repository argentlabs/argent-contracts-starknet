use argent::offchain_message::interface::{
    StarkNetDomain, StructHashStarkNetDomain, IOffChainMessageHashRev0, IStructHashRev0
};
use argent::outside_execution::interface::{OutsideExecution};
use hash::{HashStateTrait, HashStateExTrait};
use pedersen::PedersenTrait;
use starknet::{get_tx_info, get_contract_address, account::Call};

const OUTSIDE_CALL_TYPE_HASH: felt252 =
    selector!("OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)");


const OUTSIDE_EXECUTION_TYPE_HASH: felt252 =
    selector!(
        "OutsideExecution(caller:felt,nonce:felt,execute_after:felt,execute_before:felt,calls_len:felt,calls:OutsideCall*)OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)"
    );


impl StructHashOutsideExecution of IStructHashRev0<OutsideExecution> {
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
            .update_with(OUTSIDE_EXECUTION_TYPE_HASH)
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

impl StructHashCall of IStructHashRev0<Call> {
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
