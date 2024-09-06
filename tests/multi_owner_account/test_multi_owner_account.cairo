use argent::presets::argent_account::ArgentAccount;
use argent::signer::signer_signature::{
    StarknetSigner, Signer, SignerSignature, SignerSignatureTrait, StarknetSignature, SignerTrait,
    starknet_signer_from_pubkey,
};
use hash::HashStateTrait;
use pedersen::PedersenTrait;
use snforge_std::{
    signature::{KeyPairTrait, stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl}},
    start_cheat_caller_address_global, start_cheat_transaction_version_global, EventSpyTrait, EventSpyAssertionsTrait,
    ContractClassTrait, spy_events
};
use starknet::contract_address_const;
use super::super::{
    ARGENT_ACCOUNT_ADDRESS, ITestMultiOwnerAccountDispatcherTrait, initialize_mo_account_with, initialize_mo_account,
    initialize_mo_account_without_guardian, Felt252TryIntoStarknetSigner, OWNER, WRONG_OWNER
};

// TODO: this is only a subset all the test for the PoC

#[test]
fn initialize() {
    let account = initialize_mo_account_with(1, 2);
    assert_eq!(account.get_owner_guid(), starknet_signer_from_pubkey(1).into_guid());
    assert_eq!(account.get_guardian_guid().unwrap(), starknet_signer_from_pubkey(2).into_guid());
    assert!(account.get_guardian_backup_guid().is_none());
}

#[test]
fn initialized_no_guardian_no_backup() {
    let account = initialize_mo_account_with(1, 0);
    assert_eq!(account.get_owner_guid(), starknet_signer_from_pubkey(1).into_guid());
    assert!(account.get_guardian_guid().is_none());
    assert!(account.get_guardian_backup_guid().is_none());
}

#[test]
fn change_guardian() {
    let account = initialize_mo_account();
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
#[should_panic(expected: ('argent/backup-should-be-null',))]
fn change_guardian_to_zero() {
    let account = initialize_mo_account();
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(42));
    let guardian: Option<Signer> = Option::None;
    account.change_guardian_backup(guardian_backup);
    assert!(account.get_guardian_backup().is_non_zero());

    account.change_guardian(guardian);
}

#[test]
fn change_guardian_to_zero_without_guardian_backup() {
    let account = initialize_mo_account();
    let guardian: Option<Signer> = Option::None;
    account.change_guardian(guardian);
    assert!(account.get_guardian().is_zero());
    assert!(account.get_guardian_backup().is_zero());
}

#[test]
fn change_guardian_backup() {
    let account = initialize_mo_account();
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
    let account = initialize_mo_account();
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(42));
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.change_guardian_backup(guardian_backup);
}

#[test]
fn change_guardian_backup_to_zero() {
    let account = initialize_mo_account();
    let guardian_backup: Option<Signer> = Option::None;
    account.change_guardian_backup(guardian_backup);
    assert_eq!(account.get_guardian_backup(), 0);
}

#[test]
#[should_panic(expected: ('argent/guardian-required',))]
fn change_guardian_backup_invalid_guardian_backup() {
    let account = initialize_mo_account_without_guardian();
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(22));
    assert_eq!(account.get_guardian(), 0);
    account.change_guardian_backup(guardian_backup);
}

#[test]
#[should_panic(expected: ('argent/non-null-caller',))]
fn cant_call_validate() {
    let account = initialize_mo_account();
    start_cheat_caller_address_global(contract_address_const::<42>());
    account.__validate__(array![]);
}

