use argent::recovery::interface::{EscapeEnabled, EscapeStatus};
use starknet::ContractAddress;

/// @notice Escape represent a call that will be performed on the account when the escape is ready
/// @param ready_at when the escape can be completed
/// @param call_hash the hash of the EscapeCall to be performed
#[derive(Drop, Serde, Copy, starknet::Store)]
struct Escape {
    ready_at: u64,
    call_hash: felt252
}

/// @notice The call to be perfomed once the escape is Ready
#[derive(Drop, Serde)]
struct EscapeCall {
    selector: felt252,
    calldata: Array<felt252>
}

#[starknet::interface]
trait IExternalRecovery<TContractState> {
    /// @notice Enables/Disables recovery and sets the recovery parameters
    fn toggle_escape(
        ref self: TContractState, is_enabled: bool, security_period: u64, expiry_period: u64, guardian: ContractAddress
    );
    fn get_guardian(self: @TContractState) -> ContractAddress;
    /// @notice Triggers the escape.
    /// @param call Call to trigger on the account to recover the account
    /// @dev This function must be called by the guardian.
    fn trigger_escape(ref self: TContractState, call: EscapeCall);
    /// @notice Executes the escape. The function can be called by any external contract
    /// @param call Call provided to `trigger_escape`
    fn execute_escape(ref self: TContractState, call: EscapeCall);
    /// @notice Cancels the ongoing escape.
    fn cancel_escape(ref self: TContractState);
    /// @notice Gets the escape configuration.
    fn get_escape_enabled(self: @TContractState) -> EscapeEnabled;
    /// @notice Gets the ongoing escape if any, and its status.
    fn get_escape(self: @TContractState) -> (Escape, EscapeStatus);
}

/// @notice Escape was triggered
/// @param ready_at when the escape can be completed
/// @param call to execute to escape
#[derive(Drop, starknet::Event)]
struct EscapeTriggered {
    ready_at: u64,
    call: EscapeCall,
}

/// @notice Signer escape was completed and call was executed
/// @param call_hash hash of the executed EscapeCall
#[derive(Drop, starknet::Event)]
struct EscapeExecuted {
    call_hash: felt252
}

/// @notice Signer escape was canceled
/// @param call_hash hash of EscapeCall
#[derive(Drop, starknet::Event)]
struct EscapeCanceled {
    call_hash: felt252
}

impl DefaultEscape of Default<Escape> {
    fn default() -> Escape {
        Escape { ready_at: 0, call_hash: 0 }
    }
}
