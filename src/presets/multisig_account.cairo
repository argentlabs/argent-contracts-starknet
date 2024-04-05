#[starknet::contract(account)]
mod ArgentMultisigAccount {
    use argent::account::interface::{IAccount, IArgentAccount, Version};
    use argent::external_recovery::{external_recovery::{external_recovery_component, IExternalRecoveryCallback}};
    use argent::introspection::src5::src5_component;
    use argent::multisig::{multisig::multisig_component};
    use argent::outside_execution::{
        outside_execution::outside_execution_component, interface::IOutsideExecutionCallback
    };
    use argent::signer::signer_signature::{Signer, SignerSignature};
    use argent::signer_storage::{signer_list::{signer_list_component}};
    use argent::upgrade::{upgrade::upgrade_component, interface::{IUpgradableCallback, IUpgradableCallbackOld}};
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_protocol, assert_only_self,}, calls::execute_multicall,
        serialization::full_deserialize_or_panic,
        transaction_version::{assert_correct_invoke_version, assert_correct_deploy_account_version},
    };
    use starknet::{get_tx_info, get_execution_info, get_contract_address, VALIDATED, account::Call, ClassHash};

    const NAME: felt252 = 'ArgentMultisig';
    const VERSION: Version = Version { major: 0, minor: 2, patch: 0 };

    // Signer storage
    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    impl SignerListInternal = signer_list_component::SignerListInternalImpl<ContractState>;
    // Multisig management
    component!(path: multisig_component, storage: multisig, event: MultisigEvents);
    #[abi(embed_v0)]
    impl Multisig = multisig_component::MultisigImpl<ContractState>;
    impl MultisigInternal = multisig_component::MultisigInternalImpl<ContractState>;
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
    // External Recovery
    component!(path: external_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ToggleExternalRecovery = external_recovery_component::ExternalRecoveryImpl<ContractState>;

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
        escape: external_recovery_component::Storage,
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
        EscapeEvents: external_recovery_component::Event,
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
    fn constructor(ref self: ContractState, new_threshold: usize, signers: Array<Signer>) {
        self.multisig.initialize(new_threshold, signers);
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let exec_info = get_execution_info().unbox();
            let tx_info = exec_info.tx_info.unbox();
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            assert(tx_info.account_deployment_data.is_empty(), 'argent/invalid-deployment-data');
            self.assert_valid_calls(calls.span());
            self.assert_valid_signatures(calls.span(), tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            let exec_info = get_execution_info().unbox();
            let tx_info = exec_info.tx_info.unbox();
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);

            // execute calls
            let retdata = execute_multicall(calls.span());
            // emit event
            let hash = tx_info.transaction_hash;
            let response = retdata.span();
            self.emit(TransactionExecuted { hash, response });
            retdata
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            if self
                .multisig
                .is_valid_signature_with_threshold(
                    hash, self.multisig.threshold.read(), signer_signatures: parse_signature_array(signature.span())
                ) {
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
            let tx_info = get_tx_info().unbox();
            assert_correct_deploy_account_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            // only 1 signer needed to deploy
            let is_valid = self
                .multisig
                .is_valid_signature_with_threshold(
                    tx_info.transaction_hash, threshold: 1, signer_signatures: parse_signature_array(tx_info.signature)
                );
            assert(is_valid, 'argent/invalid-signature');
            VALIDATED
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            VERSION
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

    impl IExternalRecoveryCallbackImpl of IExternalRecoveryCallback<ContractState> {
        #[inline(always)]
        fn execute_recovery_call(ref self: ContractState, selector: felt252, calldata: Span<felt252>) {
            let calls = array![Call { to: get_contract_address(), selector, calldata }].span();
            self.assert_valid_calls(calls);
            let retdata = execute_multicall(calls);
            self.emit(TransactionExecuted { hash: get_tx_info().unbox().transaction_hash, response: retdata.span() });
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();
            // Check basic invariants
            self.multisig.assert_valid_storage();
            assert(data.len() == 0, 'argent/unexpected-data');
            array![]
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            panic_with_felt252('argent/downgrade-not-allowed');
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
                    assert(*call.selector != selector!("execute_after_upgrade"), 'argent/forbidden-call');
                    assert(*call.selector != selector!("perform_upgrade"), 'argent/forbidden-call');
                }
            } else {
                // Make sure no call is to the account. We don't have any good reason to perform many calls to the account in the same transactions
                // and this restriction will reduce the attack surface
                assert_no_self_call(calls, account_address);
            }
        }

        fn assert_valid_signatures(
            self: @ContractState, calls: Span<Call>, execution_hash: felt252, signature: Span<felt252>
        ) {
            let valid = self
                .multisig
                .is_valid_signature_with_threshold(
                    execution_hash, self.multisig.threshold.read(), signer_signatures: parse_signature_array(signature)
                );
            assert(valid, 'argent/invalid-signature');
        }
    }

    #[must_use]
    #[inline(always)]
    fn parse_signature_array(mut raw_signature: Span<felt252>) -> Array<SignerSignature> {
        full_deserialize_or_panic(raw_signature, 'argent/invalid-signature-format')
    }
}

