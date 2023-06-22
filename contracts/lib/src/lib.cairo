mod asserts;
use asserts::{
    assert_only_self, assert_no_self_call, assert_caller_is_null, assert_correct_tx_version,
    assert_correct_declare_version
};

mod account;
use account::{ERC1271_VALIDATED, IAccount};

mod outside_execution;
use outside_execution::{OutsideExecution, hash_outside_execution_message, IOutsideExecution};

mod test_dapp;
use test_dapp::TestDapp;

mod array_ext;
use array_ext::ArrayExtTrait;

mod calls;
use calls::execute_multicall;

mod version;
use version::Version;

mod erc165;
use erc165::{
    IErc165, IErc165LibraryDispatcher, IErc165DispatcherTrait, ERC165_IERC165_INTERFACE_ID,
    ERC165_ACCOUNT_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID_OLD_1,
    ERC165_ACCOUNT_INTERFACE_ID_OLD_2,
};

mod upgrade;
use upgrade::{
    IUpgradeable, IUpgradeTarget, IUpgradeTargetLibraryDispatcher, IUpgradeTargetDispatcherTrait
};

#[cfg(test)]
mod tests;
