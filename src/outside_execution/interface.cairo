use hash::{HashStateExTrait, HashStateTrait};
use pedersen::PedersenTrait;
use starknet::{ContractAddress, get_contract_address, get_tx_info, account::Call};

// Interface ID for revision 2 of the OutsideExecute interface
// see https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md
// calculated using https://github.com/ericnordelo/src5-rs
const ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_2: felt252 =
    0x11807fbf461e989e437c2a77b6683f3e5d886f83ba27dade7b341aeb5b1def1;

/// @notice As defined in SNIP-9 https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md
/// @param caller Only the address specified here will be allowed to call `execute_from_outside`
/// As an exception, to opt-out of this check, the value 'ANY_CALLER' can be used
/// @param nonce It can be any value as long as it's unique. Prevents signature reuse
/// @param execute_after `execute_from_outside` only succeeds if executing after this time
/// @param execute_before `execute_from_outside` only succeeds if executing before this time
/// @param calls The calls that will be executed by the Account
/// Using `Call` here instead of re-declaring `OutsideCall` to avoid the conversion
#[derive(Copy, Drop, Serde)]
struct OutsideExecution {
    caller: ContractAddress,
    nonce: (felt252, felt252),
    execute_after: u64,
    execute_before: u64,
    calls: Span<Call>
}

/// @notice get_outside_execution_message_hash_rev_* is not part of the standard interface
#[starknet::interface]
trait IOutsideExecution<TContractState> {
    /// @notice This function allows anyone to submit a transaction on behalf of the account as long
    /// as they have the relevant signatures @param outside_execution The parameters of the
    /// transaction to execute @param signature A valid signature on the Eip712 message encoding of
    /// `outside_execution`
    /// @notice This function does not allow reentrancy. A call to `__execute__` or
    /// `execute_from_outside` cannot trigger another nested transaction to `execute_from_outside`.
    fn execute_from_outside_v3(
        ref self: TContractState, outside_execution: OutsideExecution, signature: Span<felt252>
    ) -> Array<Span<felt252>>;

    /// Get the status of a given nonce, true if the nonce is available to use
    fn is_valid_outside_execution_v3_nonce(
        self: @TContractState, nonce: (felt252, felt252)
    ) -> bool;

    /// Get the message hash for some `OutsideExecution` rev 2 following Eip712. Can be used to know
    /// what needs to be signed
    fn get_outside_execution_message_hash_rev_2(
        self: @TContractState, outside_execution: OutsideExecution
    ) -> felt252;

    fn get_outside_execution_v3_channel_nonce(self: @TContractState, channel: felt252) -> felt252;
}

/// This trait must be implemented when using the component `outside_execution_component` (This is
/// enforced by the compiler)
trait IOutsideExecutionCallback<TContractState> {
    /// @notice Callback performed after checking the OutsideExecution is valid
    /// @dev Make the correct access control checks in this callback
    /// @param calls The calls to be performed
    /// @param outside_execution_hash The hash of OutsideExecution
    /// @param signature The signature that the user gave for this transaction
    #[inline(always)]
    fn execute_from_outside_callback(
        ref self: TContractState,
        calls: Span<Call>,
        outside_execution_hash: felt252,
        signature: Span<felt252>,
    ) -> Array<Span<felt252>>;
}
