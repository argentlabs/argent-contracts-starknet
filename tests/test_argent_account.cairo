use argent::presets::argent_account::ArgentAccount;
use argent::signer::signer_signature::{
    Signer, SignerSignature, StarknetSignature, SignerTrait, StarknetSigner, starknet_signer_from_pubkey
};
use snforge_std::cheatcodes::contract_class::ContractClassTrait;
use snforge_std::{start_prank, declare, start_spoof, get_class_hash, ContractClass, CheatTarget, TxInfoMockTrait};
use starknet::{contract_address_const, get_tx_info};
use super::setup::{
    account_test_setup::{
        ITestArgentAccountDispatcherTrait, initialize_account_with, initialize_account,
        initialize_account_without_guardian
    },
    utils::set_tx_version_foundry,
    constants::{
        OWNER_KEY, GUARDIAN_KEY, NEW_OWNER_KEY, NEW_OWNER_SIG, WRONG_OWNER_KEY, WRONG_OWNER_SIG, ARGENT_ACCOUNT_ADDRESS
    }
};

#[test]
fn initialize() {
    let account = initialize_account_with(1, 2);
    assert(account.get_owner() == 1, 'value should be 1');
    assert(account.get_guardian() == 2, 'value should be 2');
    assert(account.get_guardian_backup() == 0, 'value should be 0');
}

#[test]
#[should_panic(expected: ('argent/invalid-tx-version',))]
fn check_transaction_version_on_execute() {
    let account = initialize_account();
    start_prank(CheatTarget::One(account.contract_address), 0.try_into().unwrap());
    set_tx_version_foundry(32, account.contract_address);
    account.__execute__(array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-tx-version',))]
fn check_transaction_version_on_validate() {
    let account = initialize_account();
    start_prank(CheatTarget::One(account.contract_address), 0.try_into().unwrap());
    set_tx_version_foundry(32, account.contract_address);
    account.__validate__(array![]);
}


#[test]
#[should_panic(expected: ('argent/zero-pubkey',))]
fn initialize_with_null_owner() {
    let class_hash = declare('ArgentAccount');
    let mut calldata = array![];
    starknet_signer_from_pubkey(0).serialize(ref calldata);
    Option::Some(starknet_signer_from_pubkey(0)).serialize(ref calldata);
    class_hash.deploy_at(@calldata, 42.try_into().unwrap()).unwrap();
}

#[test]
fn initialized_no_guardian_no_backup() {
    let account = initialize_account_with(1, 0);
    assert(account.get_owner() == 1, 'value should be 1');
    assert(account.get_guardian() == 0, 'guardian should be zero');
    assert(account.get_guardian_backup() == 0, 'guardian backup should be zero');
}

#[test]
fn erc165_unsupported_interfaces() {
    let account = initialize_account();
    assert(!account.supports_interface(0), 'Should not support 0');
    assert(!account.supports_interface(0xffffffff), 'Should not support 0xffffffff');
}

#[test]
fn erc165_supported_interfaces() {
    let account = initialize_account();
    assert(account.supports_interface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055), 'IERC165');
    assert(account.supports_interface(0x01ffc9a7), 'IERC165_OLD');
    assert(account.supports_interface(0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd), 'IACCOUNT');
    assert(account.supports_interface(0xa66bd575), 'IACCOUNT_OLD_1');
    assert(account.supports_interface(0x3943f10f), 'IACCOUNT_OLD_2');

    assert(
        account.supports_interface(0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181),
        'OUTSIDE_EXECUTION'
    );
}

#[test]
fn change_owner() {
    let account = initialize_account();
    assert(account.get_owner() == OWNER_KEY(), 'owner not correctly set');
    let new_owner_sig = NEW_OWNER_SIG();
    let new_owner_pubkey = NEW_OWNER_KEY();
    let signer_signature = SignerSignature::Starknet(
        (
            StarknetSigner { pubkey: new_owner_pubkey.try_into().unwrap() },
            StarknetSignature { r: new_owner_sig.r, s: new_owner_sig.s }
        )
    );
    account.change_owner(signer_signature);
    assert(account.get_owner() == new_owner_pubkey, 'value should be new owner pub');
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_owner_only_self() {
    let account = initialize_account();
    start_prank(CheatTarget::One(account.contract_address), 42.try_into().unwrap());
    let new_owner_sig = NEW_OWNER_SIG();
    let new_owner_pubkey = NEW_OWNER_KEY();
    let signer_signature = SignerSignature::Starknet(
        (
            StarknetSigner { pubkey: new_owner_pubkey.try_into().unwrap() },
            StarknetSignature { r: new_owner_sig.r, s: new_owner_sig.s }
        )
    );
    account.change_owner(signer_signature);
}

#[test]
#[should_panic(expected: ('Option::unwrap failed.',))]
fn change_owner_to_zero() {
    let account = initialize_account();
    let new_owner_sig = NEW_OWNER_SIG();
    let signer_signature = SignerSignature::Starknet(
        (StarknetSigner { pubkey: 0.try_into().unwrap() }, StarknetSignature { r: new_owner_sig.r, s: new_owner_sig.s })
    );
    account.change_owner(signer_signature);
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn change_owner_invalid_message() {
    let account = initialize_account();
    let new_owner = NEW_OWNER_KEY();
    let wrong_owner_sig = WRONG_OWNER_SIG();
    let signer_signature = SignerSignature::Starknet(
        (
            StarknetSigner { pubkey: new_owner.try_into().unwrap() },
            StarknetSignature { r: wrong_owner_sig.r, s: wrong_owner_sig.s }
        )
    );
    account.change_owner(signer_signature);
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn change_owner_wrong_pub_key() {
    let account = initialize_account();
    let wrong_owner = WRONG_OWNER_KEY();
    let new_owner_sig = NEW_OWNER_SIG();
    let signer_signature = SignerSignature::Starknet(
        (
            StarknetSigner { pubkey: wrong_owner.try_into().unwrap() },
            StarknetSignature { r: new_owner_sig.r, s: new_owner_sig.s }
        )
    );
    account.change_owner(signer_signature);
}

#[test]
fn change_guardian() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(22);
    account.change_guardian(Option::Some(guardian));
    assert(account.get_guardian() == guardian.into_guid(), 'value should be 22');
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_guardian_only_self() {
    let account = initialize_account();
    let guardian = Option::Some(Signer::Starknet(StarknetSigner { pubkey: 22.try_into().unwrap() }));
    start_prank(CheatTarget::One(account.contract_address), 42.try_into().unwrap());
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
    assert(account.get_guardian().is_zero(), 'value should be 0');
}

#[test]
fn change_guardian_backup() {
    let account = initialize_account();
    let guardian_backup = starknet_signer_from_pubkey(33);
    account.change_guardian_backup(Option::Some(guardian_backup));
    assert(account.get_guardian_backup() == guardian_backup.into_guid(), 'value should be 33');
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_guardian_backup_only_self() {
    let account = initialize_account();
    let guardian_backup = Option::Some(Signer::Starknet(StarknetSigner { pubkey: 42.try_into().unwrap() }));
    start_prank(CheatTarget::One(account.contract_address), 42.try_into().unwrap());
    account.change_guardian_backup(guardian_backup);
}

#[test]
fn change_guardian_backup_to_zero() {
    let account = initialize_account();
    let guardian_backup: Option<Signer> = Option::None;
    account.change_guardian_backup(guardian_backup);
    assert(account.get_guardian_backup().is_zero(), 'value should be 0');
}

#[test]
#[should_panic(expected: ('argent/guardian-required',))]
fn change_invalid_guardian_backup() {
    let account = initialize_account_without_guardian();
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(2));
    account.change_guardian_backup(guardian_backup);
}

#[test]
fn get_version() {
    let version = initialize_account().get_version();
    assert(version.major == 0, 'Version major = 0');
    assert(version.minor == 4, 'Version minor = 4');
    assert(version.patch == 0, 'Version patch = 0');
}

#[test]
fn getVersion() {
    assert(initialize_account().getVersion() == '0.4.0', 'Version should be 0.4.0');
}

#[test]
fn get_name() {
    assert(initialize_account().get_name() == 'ArgentAccount', 'Name should be ArgentAccount');
}

#[test]
fn getName() {
    assert(initialize_account().getName() == 'ArgentAccount', 'Name should be ArgentAccount');
}

#[test]
fn unsuported_supportsInterface() {
    let account = initialize_account();
    assert(account.supportsInterface(0) == 0, 'value should be false');
    assert(account.supportsInterface(0xffffffff) == 0, 'Should not support 0xffffffff');
}

#[test]
fn supportsInterface() {
    let account = initialize_account();
    assert(account.supportsInterface(0x01ffc9a7) == 1, 'ERC165_IERC165_INTERFACE_ID');
    assert(account.supportsInterface(0xa66bd575) == 1, 'ERC165_ACCOUNT_INTERFACE_ID');
    assert(account.supportsInterface(0x3943f10f) == 1, 'ERC165_OLD_ACCOUNT_INTERFACE_ID');
}
