use argent::multiowner_account::argent_account::ArgentAccount;
use argent::multiowner_account::events::SessionRevoked;
use crate::{
    ArgentAccountSetup, ITestArgentAccountDispatcherTrait, SignerKeyPairImpl, StarknetKeyPair, initialize_account,
};
use snforge_std::{EventSpyAssertionsTrait, spy_events, start_cheat_caller_address_global};

#[test]
fn test_revoke_session() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert!(!account.is_session_revoked(42));
    let mut spy = spy_events();
    account.revoke_session(42);
    assert!(account.is_session_revoked(42));
    spy
        .assert_emitted(
            @array![
                (account.contract_address, ArgentAccount::Event::SessionRevoked(SessionRevoked { session_hash: 42 })),
            ],
        );
}

#[test]
fn test_revoke_sessions() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert!(!account.is_session_revoked(42));
    assert!(!account.is_session_revoked(43));

    let mut spy = spy_events();
    account.revoke_sessions(array![42, 43]);
    assert!(account.is_session_revoked(42));
    assert!(account.is_session_revoked(43));

    spy
        .assert_emitted(
            @array![
                (account.contract_address, ArgentAccount::Event::SessionRevoked(SessionRevoked { session_hash: 42 })),
                (account.contract_address, ArgentAccount::Event::SessionRevoked(SessionRevoked { session_hash: 43 })),
            ],
        );
}

#[test]
#[should_panic(expected: ('session/already-revoked',))]
fn test_revoke_session_already_revoked() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    assert!(!account.is_session_revoked(42));
    account.revoke_session(42);
    account.revoke_session(42);
}

#[test]
#[should_panic(expected: ('session/already-revoked',))]
fn test_revoke_sessions_already_revoked() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    account.revoke_sessions(array![42, 43]);
    account.revoke_sessions(array![43, 44]);
}

#[test]
#[should_panic(expected: ('session/already-revoked',))]
fn test_revoke_sessions_duplicates() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    account.revoke_sessions(array![42, 43, 42]);
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_revoke_session_only_self() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    start_cheat_caller_address_global(42.try_into().unwrap());
    account.revoke_session(42);
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_revoke_sessions_only_self() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    start_cheat_caller_address_global(42.try_into().unwrap());
    account.revoke_sessions(array![42, 43]);
}
