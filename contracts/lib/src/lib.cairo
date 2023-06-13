mod asserts;
use asserts::assert_only_self;
use asserts::assert_no_self_call;
use asserts::assert_caller_is_null;
use asserts::assert_correct_tx_version;
use asserts::assert_correct_declare_version;

// mod span_serde;
// use span_serde::SpanSerde;

mod outside_execution;
use outside_execution::OutsideExecution;
use outside_execution::hash_outside_execution_message;

mod test_dapp;
use test_dapp::TestDapp;


mod array_ext;
use array_ext::ArrayExtTrait;

// Structures 
mod calls;
use calls::Call;
use calls::execute_multicall;

mod version;
use version::Version;
mod erc165;
use erc165::{
    IErc165, IErc165LibraryDispatcher, IErc165DispatcherTrait, ERC165_IERC165_INTERFACE_ID,
    ERC165_ACCOUNT_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID_OLD_1,
    ERC165_ACCOUNT_INTERFACE_ID_OLD_2,
};

mod erc1271;
use erc1271::{ERC1271_VALIDATED};

use starknet::ClassHash;

#[starknet::interface]
trait IAccountUpgrade<TContractState> {
    fn upgrade(
        ref self: TContractState, implementation: ClassHash, calldata: Array<felt252>
    ) -> Array<felt252>;
    fn execute_after_upgrade(ref self: TContractState, data: Array<felt252>) -> Array<felt252>;
}

#[cfg(test)]
mod tests;

