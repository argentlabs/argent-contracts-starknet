use argent::multisig_account::external_recovery::{
    EscapeCall, EscapeCanceled, EscapeTriggered, IExternalRecoveryDispatcher, IExternalRecoveryDispatcherTrait,
    external_recovery_component, get_escape_call_hash,
};
use argent::multisig_account::signer_manager::{ISignerManagerDispatcher, ISignerManagerDispatcherTrait};
use argent::recovery::EscapeStatus;
use argent::signer::signer_signature::Signer;
use argent::utils::serialization::serialize;
use crate::StarknetKeyPair;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, EventSpyTrait, declare, spy_events,
    start_cheat_block_timestamp_global, start_cheat_caller_address_global,
};
use starknet::ContractAddress;

#[starknet::contract]
mod ExternalRecoveryMock {
    use argent::multisig_account::external_recovery::{IExternalRecoveryCallback, external_recovery_component};
    use argent::multisig_account::signer_manager::{
        signer_manager_component, signer_manager_component::SignerManagerInternalImpl,
    };
    use argent::utils::calls::execute_multicall;
    use openzeppelin_security::reentrancyguard::{ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl};

    component!(path: external_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ExternalRecovery = external_recovery_component::ExternalRecoveryImpl<ContractState>;

    // Signer management
    component!(path: signer_manager_component, storage: signer_manager, event: SignerManagerEvents);
    #[abi(embed_v0)]
    impl SignerManager = signer_manager_component::SignerManagerImpl<ContractState>;

    // Reentrancy guard
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_manager: signer_manager_component::Storage,
        #[substorage(v0)]
        escape: external_recovery_component::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SignerManagerEvents: signer_manager_component::Event,
        #[flat]
        EscapeEvents: external_recovery_component::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
    }

    impl IExternalRecoveryCallbackImpl of IExternalRecoveryCallback<ContractState> {
        fn execute_recovery_call(ref self: ContractState, selector: felt252, calldata: Span<felt252>) {
            execute_multicall(
                array![starknet::account::Call { to: starknet::get_contract_address(), selector, calldata }].span(),
            );
        }
    }
}

struct CompRecoverySetup {
    recovery_component: IExternalRecoveryDispatcher,
    multisig_component: ISignerManagerDispatcher,
    guardian: ContractAddress,
    signers: Array<Signer>,
    recovery_comp_address: ContractAddress,
}

const MIN_ESCAPE_PERIOD: u64 = 10 * 60;

fn setup() -> CompRecoverySetup {
    let (contract_address, _) = declare("ExternalRecoveryMock")
        .expect('Fail depl ExternalRecoveryMock')
        .contract_class()
        .deploy(@array![])
        .expect('Deployment failed');
    start_cheat_caller_address_global(contract_address);
    let multisig_component = ISignerManagerDispatcher { contract_address };
    let signers = array![StarknetKeyPair::random().signer(), StarknetKeyPair::random().signer()];
    multisig_component.add_signers(2, signers.clone());
    let guardian = 'guardian'.try_into().unwrap();
    let recovery_component = IExternalRecoveryDispatcher { contract_address };
    recovery_component.toggle_escape(true, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD, guardian);
    CompRecoverySetup {
        recovery_component, multisig_component, guardian, signers, recovery_comp_address: contract_address,
    }
}

// Toggle

#[test]
fn test_toggle_escape() {
    let CompRecoverySetup { recovery_component, guardian, .. } = setup();
    let mut config = recovery_component.get_escape_enabled();
    assert!(config.is_enabled);
    assert_eq!(config.security_period, MIN_ESCAPE_PERIOD);
    assert_eq!(config.expiry_period, MIN_ESCAPE_PERIOD);
    assert_eq!(recovery_component.get_guardian(), guardian);

    let (_, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None);

    recovery_component.toggle_escape(false, 0, 0, 0.try_into().unwrap());
    config = recovery_component.get_escape_enabled();
    assert_eq!(config.is_enabled, false);
    assert_eq!(config.security_period, 0);
    assert_eq!(config.expiry_period, 0);
    assert_eq!(recovery_component.get_guardian(), 0.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_toggle_unauthorized() {
    let CompRecoverySetup { recovery_component, guardian, .. } = setup();
    start_cheat_caller_address_global(42.try_into().unwrap());
    recovery_component.toggle_escape(false, 0, 0, guardian);
}

#[test]
#[should_panic(expected: ('argent/invalid-guardian',))]
fn test_toggle_guardian_same_as_account() {
    let CompRecoverySetup { recovery_component, recovery_comp_address, .. } = setup();
    recovery_component.toggle_escape(true, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD, recovery_comp_address);
}

#[test]
#[should_panic(expected: ('argent/invalid-security-period',))]
fn test_toggle_small_security_period() {
    let CompRecoverySetup { recovery_component, .. } = setup();
    recovery_component.toggle_escape(true, MIN_ESCAPE_PERIOD - 1, MIN_ESCAPE_PERIOD, 0.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('argent/invalid-expiry-period',))]
fn test_toggle_small_expiry_period() {
    let CompRecoverySetup { recovery_component, .. } = setup();
    recovery_component.toggle_escape(true, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD - 1, 0.try_into().unwrap());
}


#[test]
#[should_panic(expected: ('argent/invalid-zero-guardian',))]
fn test_toggle_zero_guardian() {
    let CompRecoverySetup { recovery_component, .. } = setup();
    recovery_component.toggle_escape(true, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD, 0.try_into().unwrap());
}

fn replace_signer_call(remove: @Signer, replace_with: Signer) -> EscapeCall {
    EscapeCall { selector: selector!("replace_signer"), calldata: serialize(@(*remove, replace_with)) }
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle__true_with_not_ready_escape() {
    let CompRecoverySetup { recovery_component, guardian, signers, recovery_comp_address, .. } = setup();

    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    let call = replace_signer_call(signers[0], new_signer);
    recovery_component.trigger_escape(call);

    let (_, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::NotReady);

    start_cheat_caller_address_global(recovery_comp_address);
    recovery_component.toggle_escape(true, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD, 42.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_false_with_not_ready_escape() {
    let CompRecoverySetup { recovery_component, guardian, signers, recovery_comp_address, .. } = setup();

    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    let call = replace_signer_call(signers[0], new_signer);
    recovery_component.trigger_escape(call);

    let (_, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::NotReady);

    start_cheat_caller_address_global(recovery_comp_address);
    recovery_component.toggle_escape(false, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD, 42.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_true_with_ready_escape() {
    let CompRecoverySetup { recovery_component, guardian, signers, recovery_comp_address, .. } = setup();

    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    let call = replace_signer_call(signers[0], new_signer);
    recovery_component.trigger_escape(call);

    start_cheat_block_timestamp_global(MIN_ESCAPE_PERIOD);
    let (_, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Ready);

    start_cheat_caller_address_global(recovery_comp_address);
    recovery_component.toggle_escape(true, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD, 42.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('argent/ongoing-escape',))]
fn test_toggle_false_with_ready_escape() {
    let CompRecoverySetup { recovery_component, guardian, signers, recovery_comp_address, .. } = setup();

    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    let call = replace_signer_call(signers[0], new_signer);
    recovery_component.trigger_escape(call);

    start_cheat_block_timestamp_global(MIN_ESCAPE_PERIOD);
    let (_, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Ready);

    start_cheat_caller_address_global(recovery_comp_address);
    recovery_component.toggle_escape(false, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD, 42.try_into().unwrap());
}

#[test]
fn test_toggle_true_with_expired_escape() {
    let CompRecoverySetup { recovery_component, guardian, signers, recovery_comp_address, .. } = setup();

    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    let call = replace_signer_call(signers[0], new_signer);
    recovery_component.trigger_escape(call);

    start_cheat_block_timestamp_global(2 * MIN_ESCAPE_PERIOD);
    let (escape, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Expired);
    assert_ne!(escape.ready_at, 0, "Should not be 0");

    start_cheat_caller_address_global(recovery_comp_address);
    recovery_component.toggle_escape(true, MIN_ESCAPE_PERIOD, MIN_ESCAPE_PERIOD, 42.try_into().unwrap());

    let (escape, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None);
    assert_eq!(escape.ready_at, 0);
}

#[test]
fn test_toggle_false_with_expired_escape() {
    let CompRecoverySetup { recovery_component, guardian, signers, recovery_comp_address, .. } = setup();

    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    let call = replace_signer_call(signers[0], new_signer);
    recovery_component.trigger_escape(call);

    start_cheat_block_timestamp_global(2 * MIN_ESCAPE_PERIOD);
    let (escape, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::Expired);
    assert_ne!(escape.ready_at, 0, "Should not be 0");

    start_cheat_caller_address_global(recovery_comp_address);
    recovery_component.toggle_escape(false, 0, 0, 0.try_into().unwrap());

    let (escape, escape_status) = recovery_component.get_escape();
    assert_eq!(escape_status, EscapeStatus::None);
    assert_eq!(escape.ready_at, 0);
}

// Trigger

#[test]
fn test_trigger_escape_replace_signer() {
    let CompRecoverySetup { recovery_component, guardian, signers, .. } = setup();
    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    let call = replace_signer_call(signers[0], new_signer);
    let call_hash = get_escape_call_hash(@call);
    recovery_component.trigger_escape(call);
    let (escape, status) = recovery_component.get_escape();
    assert_eq!(escape.call_hash, call_hash);
    assert_eq!(escape.ready_at, MIN_ESCAPE_PERIOD);
    assert_eq!(status, EscapeStatus::NotReady);
}

#[test]
fn test_trigger_escape_can_override() {
    let CompRecoverySetup { recovery_component, guardian, signers, recovery_comp_address, .. } = setup();
    start_cheat_caller_address_global(guardian);

    let new_signer_1 = StarknetKeyPair::random().signer();
    recovery_component.trigger_escape(replace_signer_call(signers[0], new_signer_1));
    let new_signer_2 = StarknetKeyPair::random().signer();
    let second_call = replace_signer_call(signers[0], new_signer_2);
    let second_call_hash = get_escape_call_hash(@second_call);

    let mut spy = spy_events();
    recovery_component.trigger_escape(second_call);
    let first_call_hash = get_escape_call_hash(@replace_signer_call(signers[0], new_signer_1));
    let escape_canceled_event = external_recovery_component::Event::EscapeCanceled(
        EscapeCanceled { call_hash: first_call_hash },
    );
    spy.assert_emitted(@array![(recovery_comp_address, escape_canceled_event)]);

    let escape_event = external_recovery_component::Event::EscapeTriggered(
        EscapeTriggered { ready_at: MIN_ESCAPE_PERIOD, call: replace_signer_call(signers[0], new_signer_2) },
    );
    spy.assert_emitted(@array![(recovery_comp_address, escape_event)]);
    assert_eq!(spy.get_events().events.len(), 2);

    let (escape, _) = recovery_component.get_escape();
    assert_eq!(escape.call_hash, second_call_hash);
}

#[test]
#[should_panic(expected: ('argent/only-guardian',))]
fn test_trigger_escape_not_enabled() {
    let CompRecoverySetup { recovery_component, guardian, signers, .. } = setup();
    recovery_component.toggle_escape(false, 0, 0, 0.try_into().unwrap());
    start_cheat_caller_address_global(guardian);
    recovery_component.trigger_escape(replace_signer_call(signers[0], StarknetKeyPair::random().signer()));
}

#[test]
#[should_panic(expected: ('argent/only-guardian',))]
fn test_trigger_escape_unauthorized() {
    let CompRecoverySetup { recovery_component, signers, .. } = setup();
    start_cheat_caller_address_global(42.try_into().unwrap());
    recovery_component.trigger_escape(replace_signer_call(signers[0], StarknetKeyPair::random().signer()));
}

// Escape

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_NotReady() {
    let CompRecoverySetup { recovery_component, guardian, signers, .. } = setup();
    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    recovery_component.trigger_escape(replace_signer_call(signers[1], new_signer));
    start_cheat_block_timestamp_global(8);
    recovery_component.execute_escape(replace_signer_call(signers[1], new_signer));
}

#[test]
#[should_panic(expected: ('argent/invalid-escape',))]
fn test_execute_escape_Expired() {
    let CompRecoverySetup { recovery_component, guardian, signers, .. } = setup();
    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    recovery_component.trigger_escape(replace_signer_call(signers[1], new_signer));
    start_cheat_block_timestamp_global(28);
    recovery_component.execute_escape(replace_signer_call(signers[1], new_signer));
}

// Cancel

#[test]
fn test_cancel_escape() {
    let CompRecoverySetup {
        recovery_component, multisig_component, guardian, signers, recovery_comp_address,
    } = setup();
    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    recovery_component.trigger_escape(replace_signer_call(signers[1], new_signer));
    start_cheat_block_timestamp_global(11);
    start_cheat_caller_address_global(recovery_comp_address);
    let mut spy = spy_events();
    recovery_component.cancel_escape();
    let (escape, status) = recovery_component.get_escape();
    assert_eq!(status, EscapeStatus::None);
    assert_eq!(escape.ready_at, 0);
    assert!(multisig_component.is_signer(*signers[0]));
    assert!(multisig_component.is_signer(*signers[1]));
    assert!(!multisig_component.is_signer(new_signer));

    let call_hash = get_escape_call_hash(@replace_signer_call(signers[1], new_signer));
    assert_eq!(spy.get_events().events.len(), 1);
    let event = external_recovery_component::Event::EscapeCanceled(EscapeCanceled { call_hash });
    spy.assert_emitted(@array![(recovery_comp_address, event)]);
}

#[test]
fn test_cancel_escape_expired() {
    let CompRecoverySetup {
        recovery_component, multisig_component, guardian, signers, recovery_comp_address,
    } = setup();
    start_cheat_caller_address_global(guardian);
    let new_signer = StarknetKeyPair::random().signer();
    recovery_component.trigger_escape(replace_signer_call(signers[1], new_signer));
    start_cheat_block_timestamp_global(2 * (60 * 10) + 1);
    start_cheat_caller_address_global(recovery_comp_address);
    let mut spy = spy_events();
    recovery_component.cancel_escape();
    let (escape, status) = recovery_component.get_escape();
    assert_eq!(status, EscapeStatus::None);
    assert_eq!(escape.ready_at, 0);
    assert!(multisig_component.is_signer(*signers[0]));
    assert!(multisig_component.is_signer(*signers[1]));
    assert!(!multisig_component.is_signer(new_signer));

    let call_hash = get_escape_call_hash(@replace_signer_call(signers[1], new_signer));
    assert_eq!(spy.get_events().events.len(), 0);
    let event = external_recovery_component::Event::EscapeCanceled(EscapeCanceled { call_hash: call_hash });
    spy.assert_not_emitted(@array![(recovery_comp_address, event)]);
}

#[test]
#[should_panic(expected: ('argent/only-self',))]
fn test_cancel_escape_unauthorized() {
    let CompRecoverySetup { recovery_component, guardian, signers, .. } = setup();
    start_cheat_caller_address_global(guardian);
    recovery_component.trigger_escape(replace_signer_call(signers[1], StarknetKeyPair::random().signer()));
    start_cheat_block_timestamp_global(11);
    start_cheat_caller_address_global(42.try_into().unwrap());
    recovery_component.cancel_escape();
}

