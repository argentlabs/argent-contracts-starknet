use argent::multisig_account::external_recovery::packing::{PackEscapeEnabled};
use argent::recovery::EscapeStatus;
use starknet::ContractAddress;

/// @notice Escape represent a call that will be performed on the account when the escape is ready
/// @param ready_at when the escape can be completed
/// @param call_hash the hash of the EscapeCall to be performed
#[derive(Drop, Serde, Copy, Default, starknet::Store)]
struct Escape {
    ready_at: u64,
    call_hash: felt252
}

/// @notice The call to be performed once the escape is Ready
#[derive(Drop, Serde)]
struct EscapeCall {
    selector: felt252,
    calldata: Array<felt252>
}

/// @notice Information relative to whether the escape is enabled
/// @param is_enabled The escape is enabled
/// @param security_period Time it takes for the escape to become ready after being triggered
/// @param expiry_period The escape will be ready and can be completed for this duration
#[derive(Drop, Copy, Serde)]
struct EscapeEnabled {
    is_enabled: bool,
    security_period: u64,
    expiry_period: u64,
}


#[starknet::interface]
trait IExternalRecovery<TContractState> {
    /// @notice Enables/Disables recovery and sets the recovery parameters
    fn toggle_escape(
        ref self: TContractState, is_enabled: bool, security_period: u64, expiry_period: u64, guardian: ContractAddress
    );
    fn get_guardian(self: @TContractState) -> ContractAddress;
    /// @notice Triggers the escape
    /// @param call Call to trigger on the account to recover the account
    /// @dev This function must be called by the guardian
    fn trigger_escape(ref self: TContractState, call: EscapeCall);
    /// @notice Executes the escape
    /// @param call Call provided to `trigger_escape`
    /// @dev This function can be called by any external contract
    fn execute_escape(ref self: TContractState, call: EscapeCall);
    /// @notice Cancels the ongoing escape
    fn cancel_escape(ref self: TContractState);
    /// @notice Gets the escape configuration
    fn get_escape_enabled(self: @TContractState) -> EscapeEnabled;
    /// @notice Gets the ongoing escape if any, and its status
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
