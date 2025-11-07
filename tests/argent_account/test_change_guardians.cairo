use argent::multiowner_account::{
    argent_account::ArgentAccount, events::{GuardianAddedGuid, GuardianRemovedGuid, SignerLinked},
    guardian_manager::guardian_manager_component,
};
use argent::signer::signer_signature::SignerTrait;
use crate::{
    ArgentAccountSetup, ITestArgentAccountDispatcherTrait, SignerKeyPairImpl, StarknetKeyPair, initialize_account,
};
use snforge_std::{EventSpyAssertionsTrait, EventSpyTrait, spy_events, start_cheat_caller_address_global};

#[test]
fn change_guardians() {
    let ArgentAccountSetup { account, guardians, .. } = initialize_account();
    let guardian = guardians[0];
    let guardian_to_add = StarknetKeyPair::random().signer();
    let other_guardian = StarknetKeyPair::random().signer();
    let mut spy = spy_events();

    account
        .change_guardians(
            guardian_guids_to_remove: array![guardian.into_guid()],
            guardians_to_add: array![guardian_to_add, other_guardian],
        );
    let guardians_info = account.get_guardians_info();
    assert_eq!(guardians_info.len(), 2);
    assert_eq!(*guardians_info[0], guardian_to_add.storage_value().into());
    assert_eq!(*guardians_info[1], other_guardian.storage_value().into());

    assert_eq!(spy.get_events().events.len(), 5);
    let signer_link_event = ArgentAccount::Event::SignerLinked(
        SignerLinked { signer_guid: guardian_to_add.into_guid(), signer: guardian_to_add },
    );
    let other_signer_link_event = ArgentAccount::Event::SignerLinked(
        SignerLinked { signer_guid: other_guardian.into_guid(), signer: other_guardian },
    );
    let guardian_removed_event = guardian_manager_component::Event::GuardianRemovedGuid(
        GuardianRemovedGuid { removed_guardian_guid: guardian.into_guid() },
    );
    let guardian_added_event = guardian_manager_component::Event::GuardianAddedGuid(
        GuardianAddedGuid { new_guardian_guid: guardian_to_add.into_guid() },
    );
    let other_guardian_added_event = guardian_manager_component::Event::GuardianAddedGuid(
        GuardianAddedGuid { new_guardian_guid: other_guardian.into_guid() },
    );
    spy
        .assert_emitted(
            @array![(account.contract_address, signer_link_event), (account.contract_address, other_signer_link_event)],
        );
    spy
        .assert_emitted(
            @array![
                (account.contract_address, guardian_removed_event),
                (account.contract_address, guardian_added_event),
                (account.contract_address, other_guardian_added_event),
            ],
        );
}

#[test]
fn change_guardians_remove_all_guardians() {
    let ArgentAccountSetup { account, guardians, .. } = initialize_account();
    let guardian = guardians[0];
    let guardian_to_add = StarknetKeyPair::random().signer();
    let other_guardian = StarknetKeyPair::random().signer();

    account
        .change_guardians(
            guardian_guids_to_remove: array![], guardians_to_add: array![guardian_to_add, other_guardian],
        );

    account
        .change_guardians(
            guardian_guids_to_remove: array![
                guardian.into_guid(), guardian_to_add.into_guid(), other_guardian.into_guid(),
            ],
            guardians_to_add: array![],
        );

    assert_eq!(account.get_guardians_info(), array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-signers-len',))]
fn change_guardians_reach_limits() {
    let ArgentAccountSetup { account, .. } = initialize_account();

    let mut guardians_to_add = array![];
    for _ in 100..132_u8 {
        guardians_to_add.append(StarknetKeyPair::random().signer())
    };

    account.change_guardians(guardian_guids_to_remove: array![], :guardians_to_add);
}

#[test]
#[should_panic(expected: ('linked-set/item-not-found',))]
fn change_guardians_remove_twice() {
    let ArgentAccountSetup { account, guardians, .. } = initialize_account();
    let guardian = guardians[0];

    account
        .change_guardians(
            guardian_guids_to_remove: array![guardian.into_guid(), guardian.into_guid()], guardians_to_add: array![],
        );
}

#[test]
#[should_panic(expected: ('linked-set/already-in-set',))]
fn change_guardians_add_twice() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    let new_guardian = StarknetKeyPair::random().signer();

    account.change_guardians(guardian_guids_to_remove: array![], guardians_to_add: array![new_guardian, new_guardian]);
}

#[test]
#[should_panic(expected: ('argent/duplicated-guids',))]
fn change_guardians_duplicates() {
    let ArgentAccountSetup { account, guardians, .. } = initialize_account();
    let guardian = guardians[0];

    account
        .change_guardians(
            guardian_guids_to_remove: array![guardian.into_guid()], guardians_to_add: array![guardian.signer()],
        );
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn change_guardians_only_self() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    let guardian = StarknetKeyPair::random().signer();
    start_cheat_caller_address_global(42.try_into().unwrap());
    account.change_guardians(guardian_guids_to_remove: array![], guardians_to_add: array![guardian]);
}
