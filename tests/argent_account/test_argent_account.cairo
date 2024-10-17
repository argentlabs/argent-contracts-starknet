use argent::multiowner_account::argent_account::ArgentAccount;
use argent::signer::signer_signature::{
    StarknetSigner, Signer, SignerSignature, SignerSignatureTrait, StarknetSignature, SignerTrait,
    starknet_signer_from_pubkey,
};
use hash::{HashStateTrait, HashStateExTrait};
use poseidon::PoseidonTrait;
use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_signature_global,
    signature::{KeyPairTrait, stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl}},
    start_cheat_caller_address_global, start_cheat_transaction_version_global, EventSpyTrait, EventSpyAssertionsTrait,
    ContractClassTrait, spy_events
};
use starknet::contract_address_const;
use super::super::{
    ARGENT_ACCOUNT_ADDRESS, ITestArgentAccountDispatcherTrait, initialize_account_with, initialize_account,
    initialize_account_without_guardian, Felt252TryIntoStarknetSigner, OWNER, WRONG_OWNER
};

fn NEW_OWNER() -> (StarknetSigner, StarknetSignature) {
    let new_owner = KeyPairTrait::from_secret_key('NEW_OWNER');
    let pubkey = new_owner.public_key.try_into().expect('argent/zero-pubkey');
    let (r, s): (felt252, felt252) = new_owner.sign(new_owner_message_hash()).unwrap();
    (StarknetSigner { pubkey }, StarknetSignature { r, s })
}

fn new_owner_message_hash() -> felt252 {
    PoseidonTrait::new()
        .update_with(selector!("replace_all_owners_with_one"))
        .update_with('SN_SEPOLIA')
        .update_with(ARGENT_ACCOUNT_ADDRESS)
        .update_with(starknet_signer_from_pubkey(OWNER().pubkey).into_guid())
        .update_with(1100)
        .finalize()
}


#[test]
fn initialize() {
    let account = initialize_account_with(1, 2);
    assert_eq!(account.get_owner_guid(), starknet_signer_from_pubkey(1).into_guid());
    assert_eq!(account.get_guardian_guid().unwrap(), starknet_signer_from_pubkey(2).into_guid());
    assert!(account.get_guardian_backup_guid().is_none());
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
    assert_eq!(account.get_owner_guid(), starknet_signer_from_pubkey(1).into_guid());
    assert!(account.get_guardian_guid().is_none());
    assert!(account.get_guardian_backup_guid().is_none());
}

#[test]
fn erc165_unsupported_interfaces() {
    let account = initialize_account();
    assert!(!account.supports_interface(0));
    assert!(!account.supports_interface(0xffffffff));
}

#[test]
fn replace_all_owners_with_one() {
    let account = initialize_account();
    assert_eq!(
        account.get_owner_guid(), starknet_signer_from_pubkey(OWNER().pubkey).into_guid(), "owner not correctly set"
    );
    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    start_cheat_signature_global(array![signature.r, signature.s].span());
    account.replace_all_owners_with_one(signer_signature, 1100);
    assert_eq!(account.get_owner_guid(), signer_signature.signer().into_guid());
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn replace_all_owners_with_one_only_self() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<42>());
    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    account.replace_all_owners_with_one(signer_signature, 1100);
}

#[test]
#[should_panic(expected: ('argent/expired-signature',))]
fn replace_all_owners_with_one_timestamp_expired() {
    let account = initialize_account();
    assert_eq!(
        account.get_owner_guid(), starknet_signer_from_pubkey(OWNER().pubkey).into_guid(), "owner not correctly set"
    );
    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((signer, signature));
    start_cheat_signature_global(array![signature.r, signature.s].span());
    start_cheat_block_timestamp_global(1000);
    account.replace_all_owners_with_one(signer_signature, 999);
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn replace_all_owners_with_one_invalid_message() {
    let account = initialize_account();
    let (signer, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet(
        (signer, StarknetSignature { r: WRONG_OWNER().sig.r, s: WRONG_OWNER().sig.s })
    );
    start_cheat_signature_global(array![signature.r, signature.s].span());
    account.replace_all_owners_with_one(signer_signature, 1100);
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn replace_all_owners_with_one_wrong_pub_key() {
    let account = initialize_account();
    let (_, signature) = NEW_OWNER();
    let signer_signature = SignerSignature::Starknet((WRONG_OWNER().pubkey.try_into().unwrap(), signature));
    start_cheat_signature_global(array![signature.r, signature.s].span());
    account.replace_all_owners_with_one(signer_signature, 1100);
}

#[test]
fn change_guardian() {
    let account = initialize_account();
    let guardian = starknet_signer_from_pubkey(22);
    let mut spy = spy_events();

    account.change_guardian(Option::Some(guardian));
    assert_eq!(account.get_guardian(), 22);

    assert_eq!(spy.get_events().events.len(), 3);
    let changed_event = ArgentAccount::Event::GuardianChanged(ArgentAccount::GuardianChanged { new_guardian: 22 });
    let guid_changed_event = ArgentAccount::Event::GuardianChangedGuid(
        ArgentAccount::GuardianChangedGuid { new_guardian_guid: guardian.into_guid() }
    );
    let signer_link_event = ArgentAccount::Event::SignerLinked(
        ArgentAccount::SignerLinked { signer_guid: guardian.into_guid(), signer: guardian }
    );

    spy
        .assert_emitted(
            @array![
                (account.contract_address, changed_event),
                (account.contract_address, guid_changed_event),
                (account.contract_address, signer_link_event)
            ]
        );
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
    assert!(account.get_guardian_backup().is_non_zero());

    account.change_guardian(guardian);
}

#[test]
fn change_guardian_to_zero_without_guardian_backup() {
    let account = initialize_account();
    let guardian: Option<Signer> = Option::None;
    account.change_guardian(guardian);
    assert!(account.get_guardian().is_zero());
    assert!(account.get_guardian_backup().is_zero());
}

#[test]
fn change_guardian_backup() {
    let account = initialize_account();
    let guardian_backup = starknet_signer_from_pubkey(33);
    assert_eq!(account.get_guardian_backup(), 0);
    let mut spy = spy_events();

    account.change_guardian_backup(Option::Some(guardian_backup));
    assert_eq!(account.get_guardian_backup(), 33);

    assert_eq!(spy.get_events().events.len(), 3);
    let changed_event = ArgentAccount::Event::GuardianBackupChanged(
        ArgentAccount::GuardianBackupChanged { new_guardian_backup: 33 }
    );
    let guid_changed_event = ArgentAccount::Event::GuardianBackupChangedGuid(
        ArgentAccount::GuardianBackupChangedGuid { new_guardian_backup_guid: guardian_backup.into_guid() }
    );
    let signer_link_event = ArgentAccount::Event::SignerLinked(
        ArgentAccount::SignerLinked { signer_guid: guardian_backup.into_guid(), signer: guardian_backup }
    );

    spy
        .assert_emitted(
            @array![
                (account.contract_address, changed_event),
                (account.contract_address, guid_changed_event),
                (account.contract_address, signer_link_event)
            ]
        );
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
    assert_eq!(account.get_guardian_backup(), 0);
}

#[test]
#[should_panic(expected: ('argent/guardian-required',))]
fn change_guardian_backup_invalid_guardian_backup() {
    let account = initialize_account_without_guardian();
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(22));
    assert_eq!(account.get_guardian(), 0);
    account.change_guardian_backup(guardian_backup);
}

#[test]
fn get_version() {
    let version = initialize_account().get_version();
    assert_eq!(version.major, 0);
    assert_eq!(version.minor, 5);
    assert_eq!(version.patch, 0);
}

#[test]
fn getVersion() {
    assert_eq!(initialize_account().getVersion(), '0.5.0');
}

#[test]
fn get_name() {
    assert_eq!(initialize_account().get_name(), 'ArgentAccount');
}

#[test]
fn getName() {
    assert_eq!(initialize_account().getName(), 'ArgentAccount');
}

#[test]
fn unsupported_supportsInterface() {
    let account = initialize_account();
    assert_eq!(account.supportsInterface(0), 0);
    assert_eq!(account.supportsInterface(0xffffffff), 0);
}

#[test]
fn supportsInterface() {
    let account = initialize_account();
    assert_eq!(account.supportsInterface(0x01ffc9a7), 1);
    assert_eq!(
        account.supportsInterface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055),
        1,
        "SRC5_INTERFACE_ID"
    );
    assert_eq!(account.supportsInterface(0xa66bd575), 1);
    assert_eq!(account.supportsInterface(0x3943f10f), 1);
    assert_eq!(
        account.supportsInterface(0x2ceccef7f994940b3962a6c67e0ba4fcd37df7d131417c604f91e03caecc1cd),
        1,
        "SRC5_ACCOUNT_INTERFACE_ID"
    );

    assert_eq!(
        account.supportsInterface(0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181),
        1,
        "ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_0"
    );
    assert_eq!(
        account.supportsInterface(0x1d1144bb2138366ff28d8e9ab57456b1d332ac42196230c3a602003c89872),
        1,
        "ERC165_OUTSIDE_EXECUTION_INTERFACE_ID_REV_1"
    );
}

#[test]
#[should_panic(expected: ('argent/non-null-caller',))]
fn cant_call_validate() {
    let account = initialize_account();
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.__validate__(array![]);
}

