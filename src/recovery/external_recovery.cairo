use starknet::ContractAddress;

#[starknet::interface]
trait IToggleExternalRecovery<TContractState> {
    fn toggle_escape(
        ref self: TContractState, is_enabled: bool, security_period: u64, expiry_period: u64, guardian: ContractAddress
    );
    fn get_guardian(self: @TContractState) -> ContractAddress;
}

/// @notice Implements the recovery by defining a guardian (and external contract/account) 
/// that can trigger the recovery and replace a set of signers. 
/// The recovery can be executed by anyone after the security period.
/// The recovery can be canceled by the authorised signers through the validation logic of the account. 
#[starknet::component]
mod external_recovery_component {
    use argent::recovery::interface::{
        Escape, EscapeEnabled, EscapeStatus, IRecovery, EscapeExecuted, EscapeTriggered, EscapeCanceled
    };
    use argent::signer::signer_signature::{Signer, SignerTrait};
    use argent::signer_storage::interface::ISignerList;
    use argent::signer_storage::signer_list::{
        signer_list_component, signer_list_component::{SignerListInternalImpl, OwnerAdded, OwnerRemoved, SignerLinked}
    };
    use argent::utils::asserts::assert_only_self;
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
    use super::IToggleExternalRecovery;

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
        TContractState,
        +HasComponent<TContractState>,
        impl SignerList: signer_list_component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IRecovery<ComponentState<TContractState>> {
        /// @notice Triggers the escape. The method must be called by the guardian.
        /// @param target_signers the signers to escape ordered by increasing GUID
        /// @param new_signers the new signers to be set after the security period ordered by increasing GUID
        fn trigger_escape(
            ref self: ComponentState<TContractState>, target_signers: Array<Signer>, new_signers: Array<Signer>
        ) {
            self.assert_only_guardian();
            assert(target_signers.len() == new_signers.len(), 'argent/invalid-escape-length');

            let escape_config: EscapeEnabled = self.escape_enabled.read();
            assert(escape_config.is_enabled == 1, 'argent/recovery-disabled');

            let current_escape: Escape = self.escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            if (current_escape_status == EscapeStatus::NotReady || current_escape_status == EscapeStatus::Ready) {
                self
                    .emit(
                        EscapeCanceled {
                            target_signers: current_escape.target_signers.span(),
                            new_signers: current_escape.new_signers.span()
                        }
                    );
            }

            let mut target_signer_guids = array![];
            let mut new_signer_guids = array![];
            let mut target_signers_span = target_signers.span();
            let mut new_signers_span = new_signers.span();
            let mut last_target: u256 = 0;
            let mut last_new: u256 = 0;
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            loop {
                match target_signers_span.pop_front() {
                    Option::Some(target_signer) => {
                        let new_signer = new_signers_span.pop_front().expect('argent/wrong-length');
                        let target_guid = (*target_signer).into_guid();
                        assert((*new_signer).is_reasonable(), 'argent/invalid-signer');
                        let new_guid = (*new_signer).into_guid();
                        // target signers are different
                        assert(target_guid.into() > last_target, 'argent/invalid-target-order');
                        // new signers are different
                        assert(new_guid.into() > last_new, 'argent/invalid-new-order');
                        // target signers are in the list
                        assert(self.get_contract_mut().is_signer_in_list(target_guid), 'argent/unknown-signer');
                        target_signer_guids.append(target_guid);
                        new_signer_guids.append(new_guid);
                        last_target = target_guid.into();
                        last_new = new_guid.into();
                        signer_list_comp.emit(SignerLinked { signer_guid: new_guid, signer: *new_signer });
                    },
                    Option::None => { break; }
                };
            };
            let ready_at = get_block_timestamp() + escape_config.security_period;
            self
                .emit(
                    EscapeTriggered {
                        ready_at, target_signers: target_signer_guids.span(), new_signers: new_signer_guids.span()
                    }
                );
            let escape = Escape { ready_at, target_signers: target_signer_guids, new_signers: new_signer_guids };
            self.escape.write(escape);
        }

        /// @notice Executes the escape. The method can be called by any external contract/account.
        fn execute_escape(ref self: ComponentState<TContractState>) {
            let current_escape: Escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            let mut target_signer_guids = current_escape.target_signers.span();
            let mut new_signer_guids = current_escape.new_signers.span();
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            let (_, mut last_signer) = signer_list_comp.load();
            loop {
                match target_signer_guids.pop_front() {
                    Option::Some(signer) => {
                        let target_signer_guid = *signer;
                        let new_signer_guid = *new_signer_guids.pop_front().expect('argent/invalid-length');
                        signer_list_comp.replace_signer(target_signer_guid, new_signer_guid, last_signer);
                        signer_list_comp.emit(OwnerRemoved { removed_owner_guid: target_signer_guid });
                        signer_list_comp.emit(OwnerAdded { new_owner_guid: new_signer_guid });
                        if (target_signer_guid == last_signer) {
                            last_signer = new_signer_guid;
                        }
                    },
                    Option::None => { break; }
                }
            };

            // clear escape
            self.escape.write(Escape { ready_at: 0, target_signers: array![], new_signers: array![] });
        }

        /// @notice Cancels the ongoing escape.
        fn cancel_escape(ref self: ComponentState<TContractState>) {
            assert_only_self();
            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status != EscapeStatus::None, 'argent/invalid-escape');
            self.escape.write(Escape { ready_at: 0, target_signers: array![], new_signers: array![] });
            self
                .emit(
                    EscapeCanceled {
                        target_signers: current_escape.target_signers.span(),
                        new_signers: current_escape.new_signers.span()
                    }
                );
        }

        /// @notice Gets the escape configuration.
        fn get_escape_enabled(self: @ComponentState<TContractState>) -> EscapeEnabled {
            self.escape_enabled.read()
        }

        /// @notice Gets the ongoing escape if any, and its status.
        fn get_escape(self: @ComponentState<TContractState>) -> (Escape, EscapeStatus) {
            let escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let escape_status = self.get_escape_status(escape.ready_at, escape_config.expiry_period);
            (escape, escape_status)
        }
    }

    #[embeddable_as(ToggleExternalRecoveryImpl)]
    impl ToggleExternalRecovery<
        TContractState, +HasComponent<TContractState>
    > of IToggleExternalRecovery<ComponentState<TContractState>> {
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
                current_escape.target_signers.len() == 0 || current_escape_status == EscapeStatus::Expired,
                'argent/ongoing-escape'
            );

            if (is_enabled) {
                assert(
                    security_period != 0 && expiry_period != 0 && guardian != contract_address_const::<0>(),
                    'argent/invalid-escape-params'
                );
                self.escape_enabled.write(EscapeEnabled { is_enabled: 1, security_period, expiry_period });
                self.guardian.write(guardian);
            } else {
                assert(escape_config.is_enabled == 1, 'argent/escape-disabled');
                assert(
                    security_period == 0 && expiry_period == 0 && guardian == contract_address_const::<0>(),
                    'argent/invalid-escape-params'
                );
                self.escape_enabled.write(EscapeEnabled { is_enabled: 0, security_period, expiry_period });
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
