/// @dev 🚨 Attention: This smart contract has not undergone an audit and is not intended for production use. Use at
/// your own risk. Please exercise caution and conduct your own due diligence before interacting with this contract.
/// 🚨
#[starknet::contract(account)]
mod ArgentUserAccount {
    use argent::account::interface::{IAccount, IArgentAccount, Version};
    use argent::introspection::src5::src5_component;
    use argent::multisig::{multisig::{multisig_component, multisig_component::MultisigInternalImpl}};
    use argent::outside_execution::{
        outside_execution::outside_execution_component, interface::{IOutsideExecutionCallback}
    };
    use argent::recovery::threshold_recovery::IThresholdRecoveryInternal;
    use argent::recovery::{threshold_recovery::threshold_recovery_component};
    use argent::signer::{signer_signature::{Signer, SignerTrait, SignerSignature, SignerSignatureTrait}};
    use argent::signer_storage::{
        interface::ISignerList, signer_list::{signer_list_component, signer_list_component::SignerListInternalImpl}
    };
    use argent::upgrade::{upgrade::upgrade_component, interface::IUpgradableCallback};
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_protocol, assert_only_self,}, calls::execute_multicall,
        serialization::full_deserialize,
        transaction_version::{assert_correct_invoke_version, assert_correct_deploy_account_version},
    };
    use openzeppelin_security::reentrancyguard::ReentrancyGuardComponent;
    use starknet::{get_tx_info, get_contract_address, get_execution_info, VALIDATED, ClassHash, account::Call};

    const NAME: felt252 = 'ArgentAccount';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 4;
    const VERSION_PATCH: u8 = 0;

    // Signer storage
    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    impl SignerListInternal = signer_list_component::SignerListInternalImpl<ContractState>;
    // Multisig management
    component!(path: multisig_component, storage: multisig, event: MultisigEvents);
    #[abi(embed_v0)]
    impl Multisig = multisig_component::MultisigImpl<ContractState>;
    // Execute from outside
    component!(path: outside_execution_component, storage: execute_from_outside, event: ExecuteFromOutsideEvents);
    #[abi(embed_v0)]
    impl ExecuteFromOutside = outside_execution_component::OutsideExecutionImpl<ContractState>;
    // Introspection
    component!(path: src5_component, storage: src5, event: SRC5Events);
    #[abi(embed_v0)]
    impl SRC5 = src5_component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Legacy = src5_component::SRC5LegacyImpl<ContractState>;
    // Upgrade
    component!(path: upgrade_component, storage: upgrade, event: UpgradeEvents);
    #[abi(embed_v0)]
    impl Upgradable = upgrade_component::UpgradableImpl<ContractState>;
    // Threshold Recovery
    component!(path: threshold_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ThresholdRecovery = threshold_recovery_component::ThresholdRecoveryImpl<ContractState>;
    #[abi(embed_v0)]
    impl ToggleThresholdRecovery =
        threshold_recovery_component::ToggleThresholdRecoveryImpl<ContractState>;
    impl ThresholdRecoveryInternal = threshold_recovery_component::ThresholdRecoveryInternalImpl<ContractState>;
    // Reentrancy guard
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_list: signer_list_component::Storage,
        #[substorage(v0)]
        multisig: multisig_component::Storage,
        #[substorage(v0)]
        execute_from_outside: outside_execution_component::Storage,
        #[substorage(v0)]
        src5: src5_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
        #[substorage(v0)]
        escape: threshold_recovery_component::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SignerListEvents: signer_list_component::Event,
        #[flat]
        MultisigEvents: multisig_component::Event,
        #[flat]
        ExecuteFromOutsideEvents: outside_execution_component::Event,
        #[flat]
        SRC5Events: src5_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
        #[flat]
        EscapeEvents: threshold_recovery_component::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        TransactionExecuted: TransactionExecuted,
    }

    /// @notice Emitted when the account executes a transaction
    /// @param hash The transaction hash
    /// @param response The data returned by the methods called
    #[derive(Drop, starknet::Event)]
    struct TransactionExecuted {
        #[key]
        hash: felt252,
        response: Span<Span<felt252>>
    }

    #[constructor]
    fn constructor(ref self: ContractState, threshold: usize, signers: Array<Signer>) {
        self.multisig.initialize(threshold, signers);
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let exec_info = get_execution_info();
            let tx_info = exec_info.tx_info;
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            self.assert_valid_calls(calls.span());
            self.assert_valid_signatures(calls.span(), tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            self.reentrancy_guard.start();
            let exec_info = get_execution_info();
            let tx_info = exec_info.tx_info;
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);

            // execute calls
            let retdata = execute_multicall(calls.span());
            // emit event
            let hash = tx_info.transaction_hash;
            let response = retdata.span();
            self.emit(TransactionExecuted { hash, response });
            self.reentrancy_guard.end();
            retdata
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            let threshold = self.multisig.threshold.read();
            if self
                .multisig
                .is_valid_signature_with_threshold(hash, threshold, parse_signature_array(signature.span())) {
                VALIDATED
            } else {
                0
            }
        }
    }

    #[abi(embed_v0)]
    impl ArgentAccountImpl of IArgentAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            panic_with_felt252('argent/declare-not-available') // Not implemented yet
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            threshold: usize,
            signers: Array<Signer>
        ) -> felt252 {
            let tx_info = get_tx_info();
            assert_correct_deploy_account_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            // only 1 signer needed to deploy
            let is_valid = self
                .multisig
                .is_valid_signature_with_threshold(
                    tx_info.transaction_hash, 1, parse_signature_array(tx_info.signature)
                );
            assert(is_valid, 'argent/invalid-signature');
            VALIDATED
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            panic_with_felt252('argent/downgrade-not-allowed');
        }
    }

    impl OutsideExecutionCallbackImpl of IOutsideExecutionCallback<ContractState> {
        #[inline(always)]
        fn execute_from_outside_callback(
            ref self: ContractState, calls: Span<Call>, outside_execution_hash: felt252, signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            // validate calls
            self.assert_valid_calls(calls);
            // validate signatures
            self.assert_valid_signatures(calls, outside_execution_hash, signature);

            let retdata = execute_multicall(calls);
            self.emit(TransactionExecuted { hash: outside_execution_hash, response: retdata.span() });
            retdata
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls(self: @ContractState, calls: Span<Call>) {
            let account_address = get_contract_address();
            if calls.len() == 1 {
                let call = calls.at(0);
                if *call.to == account_address {
                    // This should only be called after an upgrade, never directly
                    assert(*call.selector != selector!("perform_upgrade"), 'argent/forbidden-call');
                }
            } else {
                // Make sure no call is to the account. We don't have any good reason to perform many calls to the
                // account in the same transactions and this restriction will reduce the attack surface
                assert_no_self_call(calls, account_address);
            }
        }

        fn assert_valid_signatures(
            self: @ContractState, calls: Span<Call>, execution_hash: felt252, signature: Span<felt252>
        ) {
            // get threshold
            let threshold = self.multisig.threshold.read();
            let first_call = calls.at(0);

            let signature_array = parse_signature_array(signature);
            let effective_threshold =
                match self.parse_escape_call(*first_call.to, *first_call.selector, *first_call.calldata, threshold) {
                Option::Some((
                    required_signatures, excluded_signer_guid
                )) => {
                    let mut signature_span = signature_array.span();
                    while !signature_span.is_empty() {
                        let signer_sig = *signature_span.pop_front().unwrap();
                        assert(signer_sig.signer().into_guid() != excluded_signer_guid, 'argent/unauthorized-signer')
                    };
                    required_signatures
                },
                Option::None => threshold
            };
            assert(
                self.multisig.is_valid_signature_with_threshold(execution_hash, effective_threshold, signature_array),
                'argent/invalid-signature'
            );
        }
    }

    #[must_use]
    #[inline(always)]
    fn parse_signature_array(mut raw_signature: Span<felt252>) -> Array<SignerSignature> {
        full_deserialize(raw_signature).expect('argent/invalid-signature-array')
    }
}
