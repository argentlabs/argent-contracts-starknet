use hash::{HashStateExTrait, HashStateTrait};
use pedersen::PedersenTrait;
use starknet::{ContractAddress, get_contract_address, get_tx_info, account::Call};

const ERC165_OUTSIDE_EXECUTION_INTERFACE_ID: felt252 = 0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181;

/// Interface ID: 0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181
// get_outside_execution_message_hash is not part of the standard interface
#[starknet::interface]
trait IOutsideExecution<TContractState> {
    /// @notice This method allows anyone to submit a transaction on behalf of the account as long as they have the relevant signatures
    /// @param outside_execution The parameters of the transaction to execute
    /// @param signature A valid signature on the Eip712 message encoding of `outside_execution`
    /// @notice This method allows reentrancy. A call to `__execute__` or `execute_from_outside` can trigger another nested transaction to `execute_from_outside`.
    fn execute_from_outside(
        ref self: TContractState, outside_execution: OutsideExecution, signature: Array<felt252>
    ) -> Array<Span<felt252>>;

    /// Get the status of a given nonce, true if the nonce is available to use
    fn is_valid_outside_execution_nonce(self: @TContractState, nonce: felt252) -> bool;

    /// Get the message hash for some `OutsideExecution` following Eip712. Can be used to know what needs to be signed
    fn get_outside_execution_message_hash(self: @TContractState, outside_execution: OutsideExecution) -> felt252;
}


/// This trait has to be implemented when using the component `outside_execution_component` (This is enforced by the compilator)
trait IOutsideExecutionCallback<TContractState> {
    /// @notice Callback performed after checking the OutsideExecution is valid
    /// @dev Make the correct access control checks in this callback
    /// @param calls The calls to be performed 
    /// @param outside_execution_hash The hash of OutsideExecution
    /// @param signature The signature that the user gave for this transaction
    #[inline(always)]
    fn execute_from_outside_callback(
        ref self: TContractState, calls: Span<Call>, outside_execution_hash: felt252, signature: Span<felt252>,
    ) -> Array<Span<felt252>>;
}

#[derive(Copy, Drop, Serde)]
struct OutsideExecution {
    /// @notice Only the address specified here will be allowed to call `execute_from_outside`
    /// As an exception, to opt-out of this check, the value 'ANY_CALLER' can be used
    caller: ContractAddress,
    /// It can be any value as long as it's unique. Prevents signature reuse
    nonce: felt252,
    /// `execute_from_outside` only succeeds if executing after this time
    execute_after: u64,
    /// `execute_from_outside` only succeeds if executing before this time
    execute_before: u64,
    /// The calls that will be executed by the Account
    /// Using `Call` here instead of redeclaring `OutsideCall` to avoid the conversion
    calls: Span<Call>
}

#[derive(Copy, Drop, Hash)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}

const STARKNET_DOMAIN_TYPE_HASH: felt252 = selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)");


const OUTSIDE_CALL_TYPE_HASH: felt252 =
    selector!("OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)");


const OUTSIDE_EXECUTION_TYPE_HASH: felt252 =
    selector!(
        "OutsideExecution(caller:felt,nonce:felt,execute_after:felt,execute_before:felt,calls_len:felt,calls:OutsideCall*)OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)"
    );

trait IOffchainMessageHash<T> {
    fn get_message_hash(self: @T) -> felt252;
}

trait IStructHash<T> {
    fn get_struct_hash(self: @T) -> felt252;
}

impl StructHashStarknetDomain of IStructHash<StarkNetDomain> {
    fn get_struct_hash(self: @StarkNetDomain) -> felt252 {
        PedersenTrait::new(0).update_with(STARKNET_DOMAIN_TYPE_HASH).update_with(*self).update_with(4).finalize()
    }
}

impl StructHashOutsideExecution of IStructHash<OutsideExecution> {
    fn get_struct_hash(self: @OutsideExecution) -> felt252 {
        let mut state = PedersenTrait::new(0);
        let mut calls_span = *self.calls;
        let calls_len = (*self.calls).len().into();
        let calls_hash = loop {
            match calls_span.pop_front() {
                Option::Some(call) => state = state.update((call.get_struct_hash())),
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

impl StructHashCall of IStructHash<Call> {
    fn get_struct_hash(self: @Call) -> felt252 {
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
            .update(OUTSIDE_CALL_TYPE_HASH)
            .update((*self.to).into())
            .update(*self.selector)
            .update(calldata_len)
            .update(calldata_hash)
            .update(5)
            .finalize()
    }
}

impl OffchainMessageHashSession of IOffchainMessageHash<OutsideExecution> {
    fn get_message_hash(self: @OutsideExecution) -> felt252 {
        let domain = StarkNetDomain {
            name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id,
        };

        PedersenTrait::new(0)
            .update('StarkNet Message')
            .update(domain.get_struct_hash())
            .update(get_contract_address().into())
            .update((*self).get_struct_hash())
            .update(4)
            .finalize()
    }
}
