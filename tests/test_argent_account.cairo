use argent::signer::signer_signature::{
    Signer, SignerSignature, SignerSignatureTrait, StarknetSignature, SignerTrait, starknet_signer_from_pubkey,
};
use snforge_std::{start_cheat_caller_address_global, start_cheat_transaction_version_global};
use starknet::contract_address_const;
use super::setup::{
    account_test_setup::{
        ITestArgentAccountDispatcherTrait, initialize_account_with, initialize_account,
        initialize_account_without_guardian
    },
    utils::felt252TryIntoStarknetSigner, constants::{OWNER, NEW_OWNER, WRONG_OWNER}
};

#[test]
fn initialize() {
    let account = initialize_account_with(1, 2);
    assert_eq!(account.get_owner_guid(), starknet_signer_from_pubkey(1).into_guid(), "value should be 1");
    assert_eq!(account.get_guardian_guid().unwrap(), starknet_signer_from_pubkey(2).into_guid(), "value should be 2");
    assert(account.get_guardian_backup_guid().is_none(), 'value should be 0');
}

#[test]
#[should_panic(expected: ('argent/invalid-tx-version',))]
fn check_transaction_version_on_execute() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<0>());
    start_cheat_transaction_version_global(32);
    account.__execute__(array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-tx-version',))]
fn check_transaction_version_on_validate() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<0>());
    start_cheat_transaction_version_global(32);
    account.__validate__(array![]);
}

#[test]
fn initialized_no_guardian_no_backup() {
    let account = initialize_account_with(1, 0);
    assert_eq!(account.get_owner_guid(), starknet_signer_from_pubkey(1).into_guid(), "value should be 1");
    assert(account.get_guardian_guid().is_none(), 'guardian should be zero');
    assert(account.get_guardian_backup_guid().is_none(), 'guardian backup should be zero');
}

#[test]
fn erc165_unsupported_interfaces() {
    let account = initialize_account();
    assert!(!account.supports_interface(0), "Should not support 0");
    assert!(!account.supports_interface(0xffffffff), "Should not support 0xffffffff");
}

#[test]
fn erc165_supported_interfaces() {
    let account = initialize_account();
    assert!(account.supports_interface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055), "IERC165");
    assert!(account.supports_interface(0x01ffc9a7), "IERC165_OLD");
    assert!(account.supports_interface(0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd), "IACCOUNT");
    assert!(account.supports_interface(0xa66bd575), "IACCOUNT_OLD_1");
    assert!(account.supports_interface(0x3943f10f), "IACCOUNT_OLD_2");

    assert!(
        account.supports_interface(0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181),
        "OUTSIDE_EXECUTION"
    );
}

#[test]
fn change_owner() {
    let account = initialize_account();
    assert_eq!(
        account.get_owner_guid(), starknet_signer_from_pubkey(OWNER().pubkey).into_guid(), "owner not correctly set"
    );
    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    account.change_owner(signer_signature);
    assert_eq!(account.get_owner_guid(), signer_signature.signer().into_guid(), "value should be new owner pub");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_owner_only_self() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<42>());
    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    account.change_owner(signer_signature);
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn change_owner_invalid_message() {
    let account = initialize_account();
    let (signer, _) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet(
        (signer, StarknetSignature { r: WRONG_OWNER().sig.r, s: WRONG_OWNER().sig.s })
    );
    account.change_owner(signer_signature);
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn change_owner_wrong_pub_key() {
    let account = initialize_account();
    let (_, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((WRONG_OWNER().pubkey.try_into().unwrap(), signature));
    account.change_owner(signer_signature);
}

#[test]
fn change_guardian() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(22);
    account.change_guardian(Option::Some(guardian));
    assert_eq!(account.get_guardian(), 22, "value should be 22");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_guardian_only_self() {
    let account = initialize_account();
    let guardian = Option::Some(starknet_signer_from_pubkey(22));
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.change_guardian(guardian);
}

#[test]
#[should_panic(expected: ('argent/backup-should-be-null',))]
fn change_guardian_to_zero() {
    let account = initialize_account();
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(42));
    let guardian: Option<Signer> = Option::None;
    account.change_guardian_backup(guardian_backup);
    account.change_guardian(guardian);
}

#[test]
fn change_guardian_to_zero_without_guardian_backup() {
    let account = initialize_account();
    let guardian: Option<Signer> = Option::None;
    account.change_guardian(guardian);
    assert!(account.get_guardian().is_zero(), "value should be 0");
}

#[test]
fn change_guardian_backup() {
    let account = initialize_account();
    let guardian_backup = starknet_signer_from_pubkey(33);
    assert_eq!(account.get_guardian_backup(), 0, "value should be 0");
    account.change_guardian_backup(Option::Some(guardian_backup));
    assert_eq!(account.get_guardian_backup(), 33, "value should be 33");
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_guardian_backup_only_self() {
    let account = initialize_account();
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(42));
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.change_guardian_backup(guardian_backup);
}

#[test]
fn change_guardian_backup_to_zero() {
    let account = initialize_account();
    let guardian_backup: Option<Signer> = Option::None;
    account.change_guardian_backup(guardian_backup);
    assert_eq!(account.get_guardian_backup(), 0, "value should be 0");
}

#[test]
#[should_panic(expected: ('argent/guardian-required',))]
fn change_invalid_guardian_backup() {
    let account = initialize_account_without_guardian();
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(22));
    account.change_guardian_backup(guardian_backup);
}

#[test]
fn get_version() {
    let version = initialize_account().get_version();
    assert_eq!(version.major, 0, "Version major = 0");
    assert_eq!(version.minor, 4, "Version minor = 4");
    assert_eq!(version.patch, 0, "Version patch = 0");
}

#[test]
fn getVersion() {
    assert_eq!(initialize_account().getVersion(), '0.4.0', "Version should be 0.4.0");
}

#[test]
fn get_name() {
    assert_eq!(initialize_account().get_name(), 'ArgentAccount', "Name should be ArgentAccount");
}

#[test]
fn getName() {
    assert_eq!(initialize_account().getName(), 'ArgentAccount', "Name should be ArgentAccount");
}

#[test]
fn unsupported_supportsInterface() {
    let account = initialize_account();
    assert_eq!(account.supportsInterface(0), 0, "value should be false");
    assert_eq!(account.supportsInterface(0xffffffff), 0, "Should not support 0xffffffff");
}

#[test]
fn supportsInterface() {
    let account = initialize_account();
    assert_eq!(account.supportsInterface(0x01ffc9a7), 1, "ERC165_IERC165_INTERFACE_ID");
    assert_eq!(account.supportsInterface(0xa66bd575), 1, "ERC165_ACCOUNT_INTERFACE_ID");
    assert_eq!(account.supportsInterface(0x3943f10f), 1, "ERC165_OLD_ACCOUNT_INTERFACE_ID");
}

#[test]
#[should_panic(expected: ('argent/non-null-caller',))]
fn cant_call_validate() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.__validate__(array![]);
}

