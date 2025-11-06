use argent::signer::signer_signature::{Eip191Signer, Secp256k1Signer, Signer, SignerType, starknet_signer_from_pubkey};
use crate::{
    ArgentAccountSetup, ArgentAccountWithoutGuardianSetup, ITestArgentAccountDispatcherTrait, SignerKeyPairImpl,
    StarknetKeyPair, initialize_account, initialize_account_with_owners_and_guardians,
    initialize_account_without_guardian,
};

#[test]
fn initialize() {
    let ArgentAccountSetup { account, owners, guardians, .. } = initialize_account();
    assert_eq!(account.get_owner_guid(), owners[0].into_guid());
    assert_eq!(account.get_guardian_guid().unwrap(), guardians[0].into_guid());
}

#[test]
fn initialized_no_guardian() {
    let ArgentAccountWithoutGuardianSetup { account, owners } = initialize_account_without_guardian();
    let owner_guid = owners[0].into_guid();
    assert_eq!(account.get_owner_guid(), owner_guid);
    assert!(account.get_guardian_guid().is_none());
}

#[test]
fn erc165_unsupported_interfaces() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert!(!account.supports_interface(0));
    assert!(!account.supports_interface(0xffffffff));
}

#[test]
#[should_panic(expected: ('argent/multiple-owners',))]
fn get_owner_multiple_owners() {
    let ArgentAccountSetup { account, .. } = initialize_account_with_owners_and_guardians(2, 1);

    assert_eq!(account.get_owners_info().len(), 2);
    account.get_owner();
}

#[test]
#[should_panic(expected: ('argent/multiple-owners',))]
fn get_owner_type_multiple_owners() {
    let ArgentAccountSetup { account, .. } = initialize_account_with_owners_and_guardians(2, 1);

    assert_eq!(account.get_owners_info().len(), 2);
    account.get_owner_type();
}

#[test]
#[should_panic(expected: ('argent/multiple-owners',))]
fn get_owner_guid_multiple_owners() {
    let ArgentAccountSetup { account, .. } = initialize_account_with_owners_and_guardians(2, 1);

    assert_eq!(account.get_owners_info().len(), 2);
    account.get_owner_guid();
}

#[test]
fn get_guardian() {
    let ArgentAccountSetup { account, guardians, .. } = initialize_account();
    let guardian = guardians[0].signer();
    let account_guardian = account.get_guardian();
    assert!(starknet_signer_from_pubkey(account_guardian) == guardian);
}

#[test]
#[should_panic(expected: ('argent/multiple-guardians',))]
fn get_guardian_multiple_guardians() {
    let ArgentAccountSetup { account, .. } = initialize_account_with_owners_and_guardians(1, 2);

    assert_eq!(account.get_guardians_info().len(), 2);
    account.get_guardian();
}

#[test]
fn get_guardian_no_guardian() {
    let ArgentAccountWithoutGuardianSetup { account, .. } = initialize_account_without_guardian();

    let guardian = account.get_guardian();
    assert_eq!(guardian, 0);
}

#[test]
fn get_guardian_type() {
    let ArgentAccountSetup { account, .. } = initialize_account();

    let guardian_type = account.get_guardian_type();
    assert_eq!(guardian_type, Option::Some(SignerType::Starknet));
}

#[test]
fn get_guardian_type_no_guardian() {
    let ArgentAccountWithoutGuardianSetup { account, .. } = initialize_account_without_guardian();

    let guardian_type = account.get_guardian_type();
    assert_eq!(guardian_type, Option::None);
}

#[test]
#[should_panic(expected: ('argent/multiple-guardians',))]
fn get_guardian_type_multiple_guardians() {
    let ArgentAccountSetup { account, .. } = initialize_account_with_owners_and_guardians(1, 2);

    assert_eq!(account.get_guardians_info().len(), 2);
    let _ = account.get_guardian_type();
}

#[test]
fn get_guardian_guid() {
    let ArgentAccountSetup { account, guardians, .. } = initialize_account();
    let guardian = guardians[0];

    let guardian_guid = account.get_guardian_guid().expect('missing guardian');
    assert_eq!(guardian_guid, guardian.into_guid());
}

#[test]
fn get_guardian_guid_no_guardian() {
    let ArgentAccountWithoutGuardianSetup { account, .. } = initialize_account_without_guardian();

    let guardian_guid = account.get_guardian_guid();
    assert_eq!(guardian_guid, Option::None);
}

#[test]
#[should_panic(expected: ('argent/multiple-guardians',))]
fn get_guardian_guid_multiple_guardians() {
    let ArgentAccountSetup { account, .. } = initialize_account_with_owners_and_guardians(1, 2);

    assert_eq!(account.get_guardians_info().len(), 2);
    let _ = account.get_guardian_guid();
}

#[test]
fn get_version() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    let version = account.get_version();
    assert_eq!(version.major, 0);
    assert_eq!(version.minor, 5);
    assert_eq!(version.patch, 0);
}

#[test]
fn getVersion() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert_eq!(account.getVersion(), '0.5.0');
}

#[test]
fn get_name() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert_eq!(account.get_name(), 'ArgentAccount');
}

#[test]
fn getName() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert_eq!(account.getName(), 'ArgentAccount');
}

#[test]
fn unsupported_supportsInterface() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert_eq!(account.supportsInterface(0), 0);
    assert_eq!(account.supportsInterface(0xffffffff), 0);
}

#[test]
fn supportsInterface() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert_eq!(account.supportsInterface(0x01ffc9a7), 1);
    assert_eq!(
        account.supportsInterface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055),
        1,
        "SRC5_INTERFACE_ID",
    );
    assert_eq!(account.supportsInterface(0xa66bd575), 1);
    assert_eq!(account.supportsInterface(0x3943f10f), 1);
    assert_eq!(
        account.supportsInterface(0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd),
        1,
        "SRC5_ACCOUNT_INTERFACE_ID",
    );

    assert_eq!(
        account.supportsInterface(0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181),
        1,
        "ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0",
    );
    assert_eq!(
        account.supportsInterface(0x1d1144bb2138366ff28d8e9ab57456b1d332ac42196230c3a602003c89872),
        1,
        "ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1",
    );
}

#[test]
#[should_panic(expected: ('argent/zero-pubkey-hash',))]
fn test_signer_secp256k1_wrong_pubkey_hash() {
    let ArgentAccountSetup { account, .. } = initialize_account();

    let new_owner = Signer::Secp256k1(Secp256k1Signer { pubkey_hash: 0.try_into().unwrap() });
    account.trigger_escape_owner(new_owner);
}

#[test]
#[should_panic(expected: ('argent/zero-eth-EthAddress',))]
fn test_signer_eip191Signer_wrong_pubkey_hash() {
    let ArgentAccountSetup { account, .. } = initialize_account();

    let new_owner = Signer::Eip191(Eip191Signer { eth_address: 0.try_into().unwrap() });
    account.trigger_escape_owner(new_owner);
}
