use argent::session::session::session_component;
use argent::session::session::session_component::SessionRevoked;
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
                (
                    account.contract_address,
                    session_component::Event::SessionRevoked(SessionRevoked { session_hash: 42 }),
                ),
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
#[should_panic(expected: ('argent/only-self',))]
fn test_revoke_session_only_self() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    start_cheat_caller_address_global(42.try_into().unwrap());
    account.revoke_session(42);
}

