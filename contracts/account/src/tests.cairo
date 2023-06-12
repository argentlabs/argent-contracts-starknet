mod test_argent_account;
// mod test_argent_account_signatures;

use array::ArrayTrait;
use account::ArgentAccount;
use account::IArgentAccountDispatcher;
use starknet::syscalls::{deploy_syscall, get_block_hash_syscall};
use traits::Into;
use traits::TryInto;
use result::ResultTrait;
use option::OptionTrait;
use starknet::SyscallResultTrait;
use starknet::class_hash::Felt252TryIntoClassHash;


const owner_pubkey: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const guardian_pubkey: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const wrong_owner_pubkey: felt252 =
    0x743829e0a179f8afe223fc8112dfc8d024ab6b235fd42283c4f5970259ce7b7;
const wrong_guardian_pubkey: felt252 =
    0x6eeee2b0c71d681692559735e08a2c3ba04e7347c0c18d4d49b83bb89771591;

fn initialize_default_account() -> IArgentAccountDispatcher {
    let mut calldata = ArrayTrait::new();
    calldata.append(owner_pubkey);
    calldata.append(guardian_pubkey);
    initialize_default_account_with(calldata.span())
}

fn initialize_account(owner: felt252, gaurdian: felt252) -> IArgentAccountDispatcher {
    let mut calldata = ArrayTrait::new();
    calldata.append(owner);
    calldata.append(gaurdian);
    initialize_default_account_with(calldata.span())
}

fn initialize_default_account_without_guardian() -> IArgentAccountDispatcher {
    let mut calldata = ArrayTrait::new();
    calldata.append(owner_pubkey);
    calldata.append(0);
    initialize_default_account_with(calldata.span())
}

fn initialize_default_account_with(calldata: Span<felt252>) -> IArgentAccountDispatcher {
    let (contract_address, _) = deploy_syscall(
        ArgentAccount::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata, true
    )
        .unwrap();
    IArgentAccountDispatcher { contract_address }
}

