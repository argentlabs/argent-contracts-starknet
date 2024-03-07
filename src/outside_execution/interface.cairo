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

    /// @notice Outside execution using SNIP-12 Rev 1 
    fn execute_from_outside_v2(
        ref self: TContractState, outside_execution: OutsideExecution, signature: Span<felt252>
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

