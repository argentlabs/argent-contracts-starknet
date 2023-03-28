mod tests;

mod dummy_syscalls;
mod spans;

mod asserts;
use asserts::assert_only_self;
use asserts::assert_no_self_call;
use asserts::assert_non_reentrant;
use asserts::assert_correct_tx_version;

mod argent_account;
use argent_account::ArgentAccount;

mod argent_multisig_storage;
use argent_multisig_storage::MultisigStorage;
mod argent_multisig_account;
use argent_multisig_account::ArgentMultisigAccount;

mod erc20;
use erc20::ERC20;

mod test_dapp;
use test_dapp::TestDapp;

mod multicall;
use multicall::Multicall;
use multicall::Multicall::aggregate;

mod traits;
use traits::ArrayTraitExt;

// Structures 
mod calls;
use calls::Call;
use calls::execute_multicall;

mod escape;
use escape::Escape;
use escape::StorageAccessEscape;
use escape::EscapeSerde;

mod signer_signature;
use signer_signature::SignerSignature;
use signer_signature::deserialize_array_signer_signature;
use signer_signature::SignerSignatureSize;

use array::ArrayTrait;
use gas::withdraw_gas_all;

#[inline(always)]
fn check_enough_gas() {
    match withdraw_gas_all(get_builtin_costs()) {
        Option::Some(_) => {},
        Option::None(_) => {
            let mut err_data = ArrayTrait::new();
            err_data.append('Out of gas');
            panic(err_data)
        }
    }
}
