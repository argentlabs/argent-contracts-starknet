use hash::{HashStateTrait, HashStateExTrait};
use pedersen::PedersenTrait;
use starknet::{ContractAddress, get_tx_info, get_contract_address, account::Call};

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

const OUTSIDE_EXECUTION_TYPE_HASH: felt252 =
    selector!(
        "OutsideExecution(caller:felt,nonce:felt,execute_after:felt,execute_before:felt,calls_len:felt,calls:OutsideCall*)OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)"
    );

/// @dev If you are using this component you have to support it in the `supports_interface` function
// This is achieved by adding outside_execution::ERC165_OUTSIDE_EXECUTION_INTERFACE_ID
#[starknet::component]
mod outside_execution_component {
    use starknet::{get_caller_address, get_block_timestamp};
    use super::{IOutsideExecution, OutsideExecution, hash_outside_execution_message, IOutsideExecutionCallback};

    #[storage]
    struct Storage {
        /// Keeps track of used nonces for outside transactions (`execute_from_outside`)
        outside_nonces: LegacyMap<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[embeddable_as(OutsideExecutionImpl)]
    impl OutsideExecuction<
        TContractState, +HasComponent<TContractState>, +IOutsideExecutionCallback<TContractState>, +Drop<TContractState>
    > of IOutsideExecution<ComponentState<TContractState>> {
        fn execute_from_outside(
            ref self: ComponentState<TContractState>, outside_execution: OutsideExecution, signature: Array<felt252>
        ) -> Array<Span<felt252>> {
            // Checks
            if outside_execution.caller.into() != 'ANY_CALLER' {
                assert(get_caller_address() == outside_execution.caller, 'argent/invalid-caller');
            }

            let block_timestamp = get_block_timestamp();
            assert(
                outside_execution.execute_after < block_timestamp && block_timestamp < outside_execution.execute_before,
                'argent/invalid-timestamp'
            );
            let nonce = outside_execution.nonce;
            assert(!self.outside_nonces.read(nonce), 'argent/duplicated-outside-nonce');
            self.outside_nonces.write(nonce, true);

            let outside_tx_hash = hash_outside_execution_message(@outside_execution);
            let mut state = self.get_contract_mut();
            state.execute_from_outside_callback(outside_execution.calls, outside_tx_hash, signature.span())
        }

        fn get_outside_execution_message_hash(
            self: @ComponentState<TContractState>, outside_execution: OutsideExecution
        ) -> felt252 {
            hash_outside_execution_message(@outside_execution)
        }

        fn is_valid_outside_execution_nonce(self: @ComponentState<TContractState>, nonce: felt252) -> bool {
            !self.outside_nonces.read(nonce)
        }
    }
}

// Hashing related functions

#[derive(Copy, Drop, Hash)]
struct StarkNetDomain {
    name: felt252,
    version: felt252,
    chain_id: felt252,
}


#[inline(always)]
fn hash_domain(domain: @StarkNetDomain) -> felt252 {
    PedersenTrait::new(0)
        .update_with(selector!("StarkNetDomain(name:felt,version:felt,chainId:felt)"))
        .update_with(*domain)
        .update_with(4)
        .finalize()
}

fn hash_outside_call(outside_call: @Call) -> felt252 {
    let mut state = PedersenTrait::new(0);
    let mut calldata_span = outside_call.calldata.span();
    let calldata_len = outside_call.calldata.len().into();
    let calldata_hash = loop {
        match calldata_span.pop_front() {
            Option::Some(item) => state = state.update(*item),
            Option::None => { break state.update(calldata_len).finalize(); },
        }
    };

    PedersenTrait::new(0)
        .update(selector!("OutsideCall(to:felt,selector:felt,calldata_len:felt,calldata:felt*)"))
        .update((*outside_call.to).into())
        .update(*outside_call.selector)
        .update(calldata_len)
        .update(calldata_hash)
        .update(5)
        .finalize()
}

fn hash_outside_execution(outside_execution: @OutsideExecution) -> felt252 {
    let mut state = PedersenTrait::new(0);
    let mut calls_span = *outside_execution.calls;
    let calls_len = (*outside_execution.calls).len().into();
    let calls_hash = loop {
        match calls_span.pop_front() {
            Option::Some(call) => state = state.update(hash_outside_call(call)),
            Option::None => { break state.update(calls_len).finalize(); },
        }
    };

    PedersenTrait::new(0)
        .update(OUTSIDE_EXECUTION_TYPE_HASH)
        .update((*outside_execution.caller).into())
        .update(*outside_execution.nonce)
        .update((*outside_execution.execute_after).into())
        .update((*outside_execution.execute_before).into())
        .update(calls_len)
        .update(calls_hash)
        .update(7)
        .finalize()
}

#[inline(always)]
fn hash_outside_execution_message(outside_execution: @OutsideExecution) -> felt252 {
    let domain = StarkNetDomain {
        name: 'Account.execute_from_outside', version: 1, chain_id: get_tx_info().unbox().chain_id,
    };

    PedersenTrait::new(0)
        .update('StarkNet Message')
        .update(hash_domain(@domain))
        .update(get_contract_address().into())
        .update(hash_outside_execution(outside_execution))
        .update(4)
        .finalize()
}
