/// @dev 🚨 Attention: This smart contract has not undergone an audit and is not intended for production use. Use at your own risk.  Please exercise caution and conduct your own due diligence before interacting with this contract. 🚨
use starknet::ContractAddress;

#[starknet::interface]
trait IToggleThresholdRecovery<TContractState> {
    fn toggle_escape(ref self: TContractState, is_enabled: bool, security_period: u64, expiry_period: u64);
}

#[starknet::interface]
trait IThresholdRecoveryInternal<TContractState> {
    fn parse_escape_call(
        self: @TContractState, to: ContractAddress, selector: felt252, calldata: Span<felt252>, threshold: u32
    ) -> Option<(u32, felt252)>;
}

/// @notice Implements a recovery that can be triggered by threshold - 1 signers.
/// The recovery can be executed by threshold - 1 signers after the security period.
/// The recovery can be canceled by threshold signers. 
#[starknet::component]
mod threshold_recovery_component {
    use argent::recovery::interface::{
        Escape, EscapeEnabled, EscapeStatus, IRecovery, EscapeExecuted, EscapeTriggered, EscapeCanceled
    };
    use argent::signer::signer_signature::{Signer, SignerTrait};
    use argent::signer_storage::interface::ISignerList;
    use argent::signer_storage::signer_list::{
        signer_list_component,
        signer_list_component::{SignerListInternalImpl, OwnerAddedGuid, OwnerRemovedGuid, SignerLinked}
    };
    use argent::utils::asserts::assert_only_self;
    use core::array::ArrayTrait;
    use starknet::{get_block_timestamp, get_contract_address, ContractAddress, account::Call};
    use super::{IThresholdRecoveryInternal, IToggleThresholdRecovery};

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
        EscapeCanceled: EscapeCanceled,
    }

    #[embeddable_as(ThresholdRecoveryImpl)]
    impl ThresholdRecovery<
        TContractState,
        +HasComponent<TContractState>,
        impl SignerList: signer_list_component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IRecovery<ComponentState<TContractState>> {
        /// @notice Triggers the escape. The function must be called through the __validate__ method
        /// and authorized by threshold-1 signers.
        fn trigger_escape(
            ref self: ComponentState<TContractState>, target_signers: Array<Signer>, new_signers: Array<Signer>
        ) {
            assert_only_self();
            assert(target_signers.len() == 1 && new_signers.len() == 1, 'argent/invalid-escape-length');

            let escape_config: EscapeEnabled = self.escape_enabled.read();
            assert(escape_config.is_enabled, 'argent/escape-disabled');

            let target_signer_guid = (*target_signers[0]).into_guid();
            let new_signer_guid = (*new_signers[0]).into_guid();
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            signer_list_comp.emit(SignerLinked { signer_guid: new_signer_guid, signer: *new_signers.at(0) });

            let current_escape = self.escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            if current_escape_status == EscapeStatus::NotReady || current_escape_status == EscapeStatus::Ready {
                // can only override an escape with a target signer of lower priority than the current one
                let current_escaped_signer = *current_escape.target_signers.at(0);
                assert(
                    self.get_contract().is_signer_before(current_escaped_signer, target_signer_guid),
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
                        ready_at,
                        target_signers: array![target_signer_guid].span(),
                        new_signers: array![new_signer_guid].span()
                    }
                );
        }

        /// @notice Executes the escape. The function must be called through the __validate__ method
        /// and authorized by threshold-1 signers.
        fn execute_escape(ref self: ComponentState<TContractState>) {
            assert_only_self();

            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            // replace signer
            let target_signer_guid = *current_escape.target_signers.at(0);
            let new_signer_guid = *current_escape.new_signers.at(0);
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            let (_, last_signer) = signer_list_comp.load();
            signer_list_comp.replace_signer(target_signer_guid, new_signer_guid, last_signer);
            self
                .emit(
                    EscapeExecuted {
                        target_signers: current_escape.target_signers.span(),
                        new_signers: current_escape.new_signers.span()
                    }
                );
            signer_list_comp.emit(OwnerRemovedGuid { removed_owner_guid: target_signer_guid });
            signer_list_comp.emit(OwnerAddedGuid { new_owner_guid: new_signer_guid });

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

    #[embeddable_as(ToggleThresholdRecoveryImpl)]
    impl ToggleThresholdRecovery<
        TContractState, +HasComponent<TContractState>
    > of IToggleThresholdRecovery<ComponentState<TContractState>> {
        fn toggle_escape(
            ref self: ComponentState<TContractState>, is_enabled: bool, security_period: u64, expiry_period: u64
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

            if is_enabled {
                assert(security_period != 0 && expiry_period != 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: true, security_period, expiry_period });
            } else {
                assert(escape_config.is_enabled, 'argent/escape-disabled');
                assert(security_period == 0 && expiry_period == 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: false, security_period, expiry_period });
            }
        }
    }

    #[embeddable_as(ThresholdRecoveryInternalImpl)]
    impl ThresholdRecoveryInternal<
        TContractState, +HasComponent<TContractState>, +ISignerList<TContractState>
    > of IThresholdRecoveryInternal<ComponentState<TContractState>> {
        fn parse_escape_call(
            self: @ComponentState<TContractState>,
            to: ContractAddress,
            selector: felt252,
            mut calldata: Span<felt252>,
            threshold: u32
        ) -> Option<(u32, felt252)> {
            if to == get_contract_address() {
                if selector == selector!("trigger_escape_signer") {
                    // check we can do recovery
                    let escape_config: EscapeEnabled = self.escape_enabled.read();
                    assert(escape_config.is_enabled && threshold > 1, 'argent/recovery-unavailable');
                    // get escaped signer
                    let escaped_signer: Signer = Serde::deserialize(ref calldata).expect('argent/invalid-calldata');
                    let escaped_signer_guid = escaped_signer.into_guid();
                    // check it is a valid signer
                    let is_signer = self.get_contract().is_signer_in_list(escaped_signer_guid);
                    assert(is_signer, 'argent/escaped-not-signer');
                    // return
                    return Option::Some((threshold - 1, escaped_signer_guid));
                } else if selector == selector!("escape_signer") {
                    // check we can do recovery
                    let escape_config: EscapeEnabled = self.escape_enabled.read();
                    assert(escape_config.is_enabled && threshold > 1, 'argent/recovery-unavailable');
                    // get escaped signer
                    let current_escape: Escape = self.escape.read();
                    let escaped_signer_guid = *current_escape.target_signers.at(0);
                    // return
                    return Option::Some((threshold - 1, escaped_signer_guid));
                }
            }
            Option::None
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

