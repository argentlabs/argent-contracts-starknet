#[starknet::component]
mod threshold_recovery_component {
    use argent::recovery::interface::{Escape, EscapeEnabled, EscapeStatus, IRecovery, IRecoveryInternal};
    use argent::signer::interface::ISignerList;
    use argent::signer::signer_list::{signer_list_component, signer_list_component::SignerListInternalImpl};
    use argent::signer::signer_signature::{Signer, IntoGuid};
    use argent::utils::asserts::assert_only_self;
    use core::array::ArrayTrait;
    use starknet::{get_block_timestamp, get_contract_address, ContractAddress, account::Call};

    #[storage]
    struct Storage {
        escape_enabled: EscapeEnabled,
        escape: Escape,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        EscapeTriggered: EscapeTriggered,
        EscapeExecuted: EscapeExecuted,
    }

    /// @notice Guardian escape was triggered by the owner
    /// @param ready_at when the escape can be completed
    /// @param target_signer the escaped signer address
    /// @param new_signer the new signer address to be set after the security period
    #[derive(Drop, starknet::Event)]
    struct EscapeTriggered {
        ready_at: u64,
        target_signers: Array<felt252>,
        new_signers: Array<felt252>
    }

    /// @notice Signer escape was completed and there is a new signer
    /// @param target_signer the escaped signer address
    /// @param new_signer the new signer address
    #[derive(Drop, starknet::Event)]
    struct EscapeExecuted {
        target_signers: Array<felt252>,
        new_signers: Array<felt252>
    }

    #[embeddable_as(ThresholdRecoveryImpl)]
    impl ThresholdRecovery<
        TContractState, +HasComponent<TContractState>, +ISignerList<TContractState>, +Drop<TContractState>
    > of IRecovery<ComponentState<TContractState>> {
        fn toggle_escape(
            ref self: ComponentState<TContractState>, is_enabled: bool, security_period: u64, expiry_period: u64
        ) {
            assert_only_self();
            // cannot toggle escape if there is an ongoing escape
            let escape_config = self.escape_enabled.read();
            let current_escape = self.escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            let current_escaped_signer = current_escape.target_signers.at(0);
            assert(
                *current_escaped_signer == 0 || current_escape_status == EscapeStatus::Expired, 'argent/ongoing-escape'
            );

            if (is_enabled) {
                assert(escape_config.is_enabled == 0, 'argent/escape-enabled');
                assert(security_period != 0 && expiry_period != 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: 1, security_period, expiry_period });
            } else {
                assert(escape_config.is_enabled == 1, 'argent/escape-disabled');
                assert(security_period == 0 && expiry_period == 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: 0, security_period, expiry_period });
            }
        }

        fn trigger_escape(
            ref self: ComponentState<TContractState>, target_signers: Array<Signer>, new_signers: Array<Signer>
        ) {
            assert_only_self();
            assert(target_signers.len() == 1 && new_signers.len() == 1, 'argent/invalid-escape-length');

            let target_signer_guid = (*target_signers.at(0)).into_guid().expect('argent/invalid-target-guid');
            let new_signer_guid = (*new_signers.at(0)).into_guid().expect('argent/invalid-new-signer-guid');
            //TODO self.emit(SignerLinked { signer_guid: new_signer_guid, signer: new_signer });

            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            let current_escaped_signer = current_escape.target_signers.at(0);
            if (*current_escaped_signer != 0 && current_escape_status == EscapeStatus::Ready) {
                // can only override an escape with a target signer of lower priority than the current one
                assert(
                    self.get_contract().is_signer_before(*current_escaped_signer, target_signer_guid),
                    'argent/cannot-override-escape'
                );
            }
            let ready_at = get_block_timestamp() + escape_config.security_period;
            let escape = Escape {
                ready_at, target_signers: array![target_signer_guid], new_signers: array![new_signer_guid]
            };
            self.escape.write(escape);
            self
                .emit(
                    EscapeTriggered {
                        ready_at, target_signers: array![target_signer_guid], new_signers: array![new_signer_guid]
                    }
                );
        }

        fn execute_escape(ref self: ComponentState<TContractState>) {
            assert_only_self();

            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            // replace signer
            let target_signer_guid = *current_escape.target_signers.at(0);
            let new_signer_guid = *current_escape.new_signers.at(0);
            let mut state = self.get_contract_mut();
            let (_, last_signer) = state.load();
            state.replace_signer(target_signer_guid, new_signer_guid, last_signer);
            self
                .emit(
                    EscapeExecuted { target_signers: array![target_signer_guid], new_signers: array![new_signer_guid] }
                );
            // TODO self.emit(OwnerRemoved { removed_owner_guid: current_escape.target_signer });
            // TODO self.emit(OwnerAdded { new_owner_guid: current_escape.new_signer });

            // clear escape
            self.escape.write(Escape { ready_at: 0, target_signers: array![], new_signers: array![] });
        }

        fn cancel_escape(ref self: ComponentState<TContractState>) {
            assert_only_self();
            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status != EscapeStatus::None, 'argent/invalid-escape');
            self.escape.write(Escape { ready_at: 0, target_signers: array![], new_signers: array![] });
        // TODO self.emit(EscapeCanceled { target_signer: current_escape.target_signer, new_signer: current_escape.new_signer });
        }
    }

    #[embeddable_as(ThresholdRecoveryInternalImpl)]
    impl ThresholdRecoveryInternal<
        TContractState, +HasComponent<TContractState>, +ISignerList<TContractState>
    > of IRecoveryInternal<ComponentState<TContractState>> {
        fn parse_escape_call(
            self: @ComponentState<TContractState>,
            to: ContractAddress,
            selector: felt252,
            mut calldata: Span<felt252>,
            threshold: u32
        ) -> (bool, u32, felt252) {
            if (to == get_contract_address()) {
                if (selector == selector!("trigger_escape_signer")) {
                    // check we can do recovery
                    let escape_config: EscapeEnabled = self.escape_enabled.read();
                    assert(escape_config.is_enabled == 1 && threshold > 1, 'argent/recovery-unavailable');
                    // get escaped signer
                    //let mut calldata: Span<felt252> = calldata;
                    let escaped_signer: Signer = Serde::deserialize(ref calldata).expect('argent/invalid-calldata');
                    let escaped_signer_guid = escaped_signer.into_guid().expect('argent/invalid-signer-guid');
                    // check it is a valid signer
                    let is_signer = self.get_contract().is_signer_in_list(escaped_signer_guid);
                    assert(is_signer, 'argent/escaped-not-signer');
                    // return
                    return (true, threshold - 1, escaped_signer_guid);
                } else if (selector == selector!("escape_signer")) {
                    // check we can do recovery
                    let escape_config: EscapeEnabled = self.escape_enabled.read();
                    assert(escape_config.is_enabled == 1 && threshold > 1, 'argent/recovery-unavailable');
                    // get escaped signer
                    let current_escape: Escape = self.escape.read();
                    let escaped_signer_guid = *current_escape.target_signers.at(0);
                    // return
                    return (true, threshold - 1, escaped_signer_guid);
                }
            }
            return (false, 0, 0);
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
    }
}

