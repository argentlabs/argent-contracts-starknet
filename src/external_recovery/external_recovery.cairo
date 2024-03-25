use argent::external_recovery::interface::{EscapeCall, Escape};
use argent::recovery::interface::{EscapeEnabled, EscapeStatus};

use argent::utils::serialization::serialize;
use starknet::ContractAddress;

/// This trait has to be implemented when using the component `external_recovery`
trait IExternalRecoveryCallback<TContractState> {
    #[inline(always)]
    fn execute_recovery_call(ref self: TContractState, selector: felt252, calldata: Span<felt252>);
}


/// @notice Implements the recovery by defining a guardian (and external contract/account) 
/// that can trigger the recovery and replace a set of signers. 
/// The recovery can be executed by anyone after the security period.
/// The recovery can be canceled by the authorised signers through the validation logic of the account. 
#[starknet::component]
mod external_recovery_component {
    use argent::external_recovery::interface::{
        IExternalRecovery, EscapeCall, Escape, EscapeTriggered, EscapeExecuted, EscapeCanceled,
    };
    use argent::recovery::interface::{EscapeEnabled, EscapeStatus};
    use argent::signer::signer_signature::{Signer, SignerTrait};
    use argent::signer_storage::interface::ISignerList;
    use argent::signer_storage::signer_list::{
        signer_list_component, signer_list_component::{SignerListInternalImpl, OwnerAdded, OwnerRemoved, SignerLinked}
    };
    use argent::utils::asserts::assert_only_self;
    use argent::utils::serialization::serialize;
    use core::array::ArrayTrait;
    use core::array::SpanTrait;
    use core::debug::PrintTrait;
    use core::option::OptionTrait;
    use core::result::ResultTrait;
    use core::traits::TryInto;
    use starknet::{
        get_block_timestamp, get_contract_address, get_caller_address, ContractAddress, account::Call,
        contract_address::contract_address_const
    };
    use super::{IExternalRecoveryCallback, get_escape_call_hash};

    #[storage]
    struct Storage {
        escape_enabled: EscapeEnabled,
        escape: Escape,
        guardian: ContractAddress
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        EscapeTriggered: EscapeTriggered,
        EscapeExecuted: EscapeExecuted,
        EscapeCanceled: EscapeCanceled,
    }


    #[embeddable_as(ExternalRecoveryImpl)]
    impl ExternalRecovery<
        TContractState, +HasComponent<TContractState>, +IExternalRecoveryCallback<TContractState>, +Drop<TContractState>
    > of IExternalRecovery<ComponentState<TContractState>> {
        /// @notice Triggers the escape. The method must be called by the guardian.
        /// @param call Call to trigger on the account to recover the account
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
                'argent/invalid-selector'
            );

            let current_escape: Escape = self.escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            if (current_escape_status == EscapeStatus::NotReady || current_escape_status == EscapeStatus::Ready) {
                self.emit(EscapeCanceled { call_hash });
            }

            let ready_at = get_block_timestamp() + escape_config.security_period;
            self.emit(EscapeTriggered { ready_at, call });
            let escape = Escape { ready_at, call_hash };
            self.escape.write(escape);
        }

        fn execute_escape(ref self: ComponentState<TContractState>, call: EscapeCall) {
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
        }

        fn cancel_escape(ref self: ComponentState<TContractState>) {
            assert_only_self();
            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status != EscapeStatus::None, 'argent/invalid-escape');
            self.escape.write(Default::default());
            self.emit(EscapeCanceled { call_hash: current_escape.call_hash });
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
            guardian: ContractAddress
        ) {
            assert_only_self();
            // cannot toggle escape if there is an ongoing escape
            let escape_config = self.escape_enabled.read();
            let current_escape = self.escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(
                current_escape.ready_at == 0 || current_escape_status == EscapeStatus::Expired, 'argent/ongoing-escape'
            );

            if is_enabled {
                assert(
                    security_period != 0 && expiry_period != 0 && guardian != contract_address_const::<0>(),
                    'argent/invalid-escape-params'
                );
                self.escape_enabled.write(EscapeEnabled { is_enabled: true, security_period, expiry_period });
                self.guardian.write(guardian);
            } else {
                assert(escape_config.is_enabled, 'argent/escape-disabled');
                assert(
                    security_period == 0 && expiry_period == 0 && guardian == contract_address_const::<0>(),
                    'argent/invalid-escape-params'
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
            self: @ComponentState<TContractState>, escape_ready_at: u64, expiry_period: u64
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
#[inline(always)]
fn get_escape_call_hash(escape_call: @EscapeCall) -> felt252 {
    poseidon::poseidon_hash_span(serialize(escape_call).span())
}
