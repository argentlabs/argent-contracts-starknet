mod asserts;
use asserts::assert_only_self;
use asserts::assert_no_self_call;
use asserts::assert_non_reentrant;
use asserts::assert_correct_tx_version;

mod span_serde;
use span_serde::SpanSerde;

mod outside_execution;
use outside_execution::OutsideExecution;
use outside_execution::hash_outside_execution_message;

// Structures 
mod calls;
use calls::Call;
use calls::execute_multicall;

mod version;
use version::Version;

#[abi]
trait IErc165 {
    fn supports_interface(interface_id: felt252) -> bool;
}

#[abi]
trait IAccountUpgrade {
    fn execute_after_upgrade(data: Array<felt252>) -> Array::<felt252>;
}

#[cfg(test)]
mod tests;
