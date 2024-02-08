use starknet::ContractAddress;

#[starknet::interface]
trait IToggleExternaldRecovery<TContractState> {
    fn toggle_escape(
        ref self: TContractState, is_enabled: bool, security_period: u64, expiry_period: u64, guardian: ContractAddress
    );
}

#[starknet::component]
mod external_recovery_component {
    use argent::recovery::interface::{
        Escape, EscapeEnabled, EscapeStatus, IRecovery, EscapeExecuted, EscapeTriggered, EscapeCanceled
    };
    use argent::signer::interface::ISignerList;
    use argent::signer::signer_list::{signer_list_component, signer_list_component::SignerListInternalImpl};
    use argent::signer::signer_signature::{Signer, IntoGuid};
    use argent::utils::asserts::assert_only_self;
    use core::array::ArrayTrait;
    use core::array::SpanTrait;
    use core::option::OptionTrait;
    use core::result::ResultTrait;
    use starknet::{
        get_block_timestamp, get_contract_address, get_caller_address, ContractAddress, account::Call,
        contract_address::contract_address_const
    };
    use super::IToggleExternaldRecovery;

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
        TContractState, +HasComponent<TContractState>, +ISignerList<TContractState>, +Drop<TContractState>
    > of IRecovery<ComponentState<TContractState>> {
        fn trigger_escape(
            ref self: ComponentState<TContractState>, target_signers: Array<Signer>, new_signers: Array<Signer>
        ) {
            self.assert_only_guardian();
            assert(target_signers.len() == new_signers.len(), 'argent/invalid-escape-length');

            let escape_config: EscapeEnabled = self.escape_enabled.read();
            assert(escape_config.is_enabled == 1, 'argent/recovery-disabled');

            let mut target_signer_guids = array![];
            let mut new_signer_guids = array![];
            let mut target_signers_span = target_signers.span();
            let mut new_signers_span = new_signers.span();
            let mut last_target: u256 = 0;
            let mut last_new: u256 = 0;
            loop {
                match target_signers_span.pop_front() {
                    Option::Some(signer) => {
                        let target_guid = (*signer).into_guid().expect('argent/invalid-guid');
                        let new_guid = (*new_signers_span.pop_front().expect('argent/wrong-length'))
                            .into_guid()
                            .expect('argent/invalid-guid');
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
                    // TODO emit SignerLinked event
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

        fn execute_escape(ref self: ComponentState<TContractState>) {
            let current_escape: Escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            let mut target_signer_guids = current_escape.target_signers.span();
            let mut new_signer_guids = current_escape.new_signers.span();
            let (_, mut last_signer) = self.get_contract().load();
            let mut state = self.get_contract_mut();
            loop {
                match target_signer_guids.pop_front() {
                    Option::Some(signer) => {
                        let target_signer_guid = *signer;
                        let new_signer_guid = *new_signer_guids.pop_front().expect('argent/invalid-length');
                        state.replace_signer(target_signer_guid, new_signer_guid, last_signer);
                        // TODO self.emit(OwnerRemoved { removed_owner_guid: *target_signer_guid });
                        // TODO self.emit(OwnerAdded { new_owner_guid: new_signer_guid });
                        if (target_signer_guid == last_signer) {
                            last_signer = new_signer_guid;
                        }
                    },
                    Option::None => { break; }
                }
            }
        }

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
    }

    #[embeddable_as(ToggleExternalRecoveryImpl)]
    impl ToggleExternalRecovery<
        TContractState, +HasComponent<TContractState>
    > of IToggleExternaldRecovery<ComponentState<TContractState>> {
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
                assert(security_period == 0 && expiry_period == 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: 0, security_period, expiry_period });
                self.guardian.write(contract_address_const::<0>());
            }
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
