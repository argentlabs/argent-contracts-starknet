use argent::recovery::EscapeStatus;
use argent::utils::serialization::serialize;
use core::num::traits::zero::Zero;
use starknet::ContractAddress;
use starknet::storage_access::StorePacking;

const SHIFT_8: felt252 = 0x100;
const SHIFT_64: felt252 = 0x10000000000000000;

/// @notice Escape represent a call that will be performed on the account when the escape is ready
/// @param ready_at when the escape can be completed
/// @param call_hash the hash of the EscapeCall to be performed
#[derive(Drop, Serde, Copy, Default, starknet::Store)]
pub struct Escape {
    pub ready_at: u64,
    pub call_hash: felt252,
}

/// @notice The call to be performed once the escape is Ready
#[derive(Drop, Serde)]
pub struct EscapeCall {
    pub selector: felt252,
    pub calldata: Array<felt252>,
}

/// @notice Information relative to whether the escape is enabled
/// @param is_enabled The escape is enabled
/// @param security_period Time it takes for the escape to become ready after being triggered
/// @param expiry_period Time it takes for the escape to expire after being ready
#[derive(Drop, Copy, Serde)]
pub struct EscapeEnabled {
    pub is_enabled: bool,
    pub security_period: u64,
    pub expiry_period: u64,
}


#[starknet::interface]
pub trait IExternalRecovery<TContractState> {
    /// @notice Enables/Disables recovery and sets the recovery parameters
    fn toggle_escape(
        ref self: TContractState, is_enabled: bool, security_period: u64, expiry_period: u64, guardian: ContractAddress,
    );

    /// @notice Gets the guardian that can trigger the escape
    fn get_guardian(self: @TContractState) -> ContractAddress;

    /// @notice Triggers the escape
    /// @param call Call to trigger on the account to recover the account
    /// @dev This function must be called by the guardian
    fn trigger_escape(ref self: TContractState, call: EscapeCall);

    /// @notice Executes the escape
    /// @param call Call provided to `trigger_escape`
    /// @dev This function can be called by any external contract
    fn execute_escape(ref self: TContractState, call: EscapeCall);

    /// @notice Cancels the ongoing escape
    fn cancel_escape(ref self: TContractState);

    /// @notice Gets the escape configuration
    fn get_escape_enabled(self: @TContractState) -> EscapeEnabled;

    /// @notice Gets the ongoing escape if any, and its status
    fn get_escape(self: @TContractState) -> (Escape, EscapeStatus);
}

/// @notice Escape was triggered
/// @param ready_at when the escape can be completed
/// @param call to execute to escape
#[derive(Drop, starknet::Event)]
pub struct EscapeTriggered {
    pub ready_at: u64,
    pub call: EscapeCall,
}

/// @notice Signer escape was completed and call was executed
/// @param call_hash hash of the executed EscapeCall
#[derive(Drop, starknet::Event)]
pub struct EscapeExecuted {
    pub call_hash: felt252,
}

/// @notice Signer escape was canceled
/// @param call_hash hash of EscapeCall
#[derive(Drop, starknet::Event)]
pub struct EscapeCanceled {
    pub call_hash: felt252,
}


/// This trait must be implemented when using the component `external_recovery`
pub trait IExternalRecoveryCallback<TContractState> {
    fn execute_recovery_call(ref self: TContractState, selector: felt252, calldata: Span<felt252>);
}

/// @notice Implements the recovery by defining a guardian (an external contract/account)
/// that can trigger the recovery and replace a set of signers
/// @dev The recovery can be executed by anyone after the security period
/// @dev The recovery can be canceled by the authorized signers
#[starknet::component]
pub mod external_recovery_component {
    use argent::multisig_account::external_recovery::{
        Escape, EscapeCall, EscapeCanceled, EscapeEnabled, EscapeExecuted, EscapeTriggered, IExternalRecovery,
    };
    use argent::recovery::EscapeStatus;
    use argent::utils::asserts::assert_only_self;
    use openzeppelin_security::reentrancyguard::{ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{
        ContractAddress, contract_address::contract_address_const, get_block_timestamp, get_caller_address,
        get_contract_address,
    };
    use super::{IExternalRecoveryCallback, get_escape_call_hash};

    /// Minimum time for the escape security period
    const MIN_ESCAPE_PERIOD: u64 = 60 * 10; // 10 minutes;

    #[storage]
    pub struct Storage {
        escape_enabled: EscapeEnabled,
        escape: Escape,
        guardian: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        EscapeTriggered: EscapeTriggered,
        EscapeExecuted: EscapeExecuted,
        EscapeCanceled: EscapeCanceled,
    }

    #[embeddable_as(ExternalRecoveryImpl)]
    impl ExternalRecovery<
        TContractState,
        +HasComponent<TContractState>,
        +IExternalRecoveryCallback<TContractState>,
        +Drop<TContractState>,
        impl ReentrancyGuard: ReentrancyGuardComponent::HasComponent<TContractState>,
    > of IExternalRecovery<ComponentState<TContractState>> {
        fn trigger_escape(ref self: ComponentState<TContractState>, call: EscapeCall) {
            self.assert_only_guardian();

            let escape_config: EscapeEnabled = self.escape_enabled.read();
            assert(escape_config.is_enabled, 'argent/recovery-disabled');
            let call_hash = get_escape_call_hash(@call);
            assert(
                call.selector == selector!("replace_signer")
                    || call.selector == selector!("remove_signers")
                    || call.selector == selector!("add_signers")
                    || call.selector == selector!("change_threshold"),
                'argent/invalid-selector',
            );

            let current_escape: Escape = self.escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            if (current_escape_status == EscapeStatus::NotReady || current_escape_status == EscapeStatus::Ready) {
                self.emit(EscapeCanceled { call_hash: current_escape.call_hash });
            }

            let ready_at = get_block_timestamp() + escape_config.security_period;
            self.emit(EscapeTriggered { ready_at, call });
            let escape = Escape { ready_at, call_hash };
            self.escape.write(escape);
        }

        fn execute_escape(ref self: ComponentState<TContractState>, call: EscapeCall) {
            let mut reentrancy_component = get_dep_component_mut!(ref self, ReentrancyGuard);
            reentrancy_component.start();
            let current_escape: Escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            let call_hash = get_escape_call_hash(@call);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');
            assert(current_escape.call_hash == get_escape_call_hash(@call), 'argent/invalid-escape-call');

            let mut callback = self.get_contract_mut();
            callback.execute_recovery_call(call.selector, call.calldata.span());

            self.emit(EscapeExecuted { call_hash });
            // clear escape
            self.escape.write(Default::default());
            reentrancy_component.end();
        }

        fn cancel_escape(ref self: ComponentState<TContractState>) {
            assert_only_self();
            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status != EscapeStatus::None, 'argent/invalid-escape');
            self.escape.write(Default::default());
            if current_escape_status != EscapeStatus::Expired {
                self.emit(EscapeCanceled { call_hash: current_escape.call_hash });
            }
        }

        fn get_escape_enabled(self: @ComponentState<TContractState>) -> EscapeEnabled {
            self.escape_enabled.read()
        }

        fn get_escape(self: @ComponentState<TContractState>) -> (Escape, EscapeStatus) {
            let escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let escape_status = self.get_escape_status(escape.ready_at, escape_config.expiry_period);
            (escape, escape_status)
        }

        fn toggle_escape(
            ref self: ComponentState<TContractState>,
            is_enabled: bool,
            security_period: u64,
            expiry_period: u64,
            guardian: ContractAddress,
        ) {
            assert_only_self();
            // cannot toggle escape if there is an ongoing escape
            let escape_config = self.escape_enabled.read();
            let current_escape = self.escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            match current_escape_status {
                EscapeStatus::None => (), // ignore
                EscapeStatus::NotReady | EscapeStatus::Ready => core::panic_with_felt252('argent/ongoing-escape'),
                EscapeStatus::Expired => self.escape.write(Default::default()),
            }

            if is_enabled {
                assert(security_period >= MIN_ESCAPE_PERIOD, 'argent/invalid-security-period');
                assert(expiry_period >= MIN_ESCAPE_PERIOD, 'argent/invalid-expiry-period');
                assert(guardian != contract_address_const::<0>(), 'argent/invalid-zero-guardian');
                assert(guardian != get_contract_address(), 'argent/invalid-guardian');
                self.escape_enabled.write(EscapeEnabled { is_enabled: true, security_period, expiry_period });
                self.guardian.write(guardian);
            } else {
                assert(escape_config.is_enabled, 'argent/escape-disabled');
                assert(
                    security_period == 0 && expiry_period == 0 && guardian == contract_address_const::<0>(),
                    'argent/invalid-escape-params',
                );
                self.escape_enabled.write(EscapeEnabled { is_enabled: false, security_period, expiry_period });
                self.guardian.write(contract_address_const::<0>());
            }
        }

        fn get_guardian(self: @ComponentState<TContractState>) -> ContractAddress {
            self.guardian.read()
        }
    }

    #[generate_trait]
    impl Private<TContractState, +HasComponent<TContractState>> of PrivateTrait<TContractState> {
        fn get_escape_status(
            self: @ComponentState<TContractState>, escape_ready_at: u64, expiry_period: u64,
        ) -> EscapeStatus {
            if escape_ready_at == 0 {
                return EscapeStatus::None;
            }

            let block_timestamp = get_block_timestamp();
            if block_timestamp < escape_ready_at {
                return EscapeStatus::NotReady;
            }
            if escape_ready_at + expiry_period <= block_timestamp {
                return EscapeStatus::Expired;
            }

            EscapeStatus::Ready
        }

        fn assert_only_guardian(self: @ComponentState<TContractState>) {
            assert(self.guardian.read() == get_caller_address(), 'argent/only-guardian');
        }
    }
}
pub fn get_escape_call_hash(escape_call: @EscapeCall) -> felt252 {
    core::poseidon::poseidon_hash_span(serialize(escape_call).span())
}


pub impl PackEscapeEnabled of StorePacking<EscapeEnabled, felt252> {
    fn pack(value: EscapeEnabled) -> felt252 {
        (value.is_enabled.into()
            + value.security_period.into() * SHIFT_8
            + value.expiry_period.into() * SHIFT_8 * SHIFT_64)
    }

    fn unpack(value: felt252) -> EscapeEnabled {
        let value: u256 = value.into();
        let shift_8: u256 = SHIFT_8.into();
        let shift_8: NonZero<u256> = shift_8.try_into().unwrap();
        let shift_64: u256 = SHIFT_64.into();
        let shift_64: NonZero<u256> = shift_64.try_into().unwrap();
        let (rest, is_enabled) = DivRem::div_rem(value, shift_8);
        let (expiry_period, security_period) = DivRem::div_rem(rest, shift_64);

        EscapeEnabled {
            is_enabled: !is_enabled.is_zero(),
            security_period: security_period.try_into().unwrap(),
            expiry_period: expiry_period.try_into().unwrap(),
        }
    }
}
