#[starknet::contract(account)]
mod ArgentMultisigAccount {
    use argent::account::{IAccount, IArgentAccount, IArgentAccountDispatcher, IArgentAccountDispatcherTrait, Version};
    use argent::introspection::src5::src5_component;
    use argent::multisig_account::external_recovery::external_recovery::{
        IExternalRecoveryCallback, external_recovery_component,
    };
    use argent::multisig_account::signer_manager::signer_manager::{
        signer_manager_component, signer_manager_component::SignerManagerInternalImpl,
    };
    use argent::multisig_account::upgrade_migration::{
        upgrade_migration_component, upgrade_migration_component::UpgradableMigrationInternalImpl,
    };
    use argent::outside_execution::{
        interface::IOutsideExecutionCallback, outside_execution::outside_execution_component,
    };
    use argent::signer::signer_signature::{Signer, SignerSignature};
    use argent::upgrade::{
        interface::{IUpgradableCallback, IUpgradableCallbackOld}, upgrade::upgrade_component,
        upgrade::upgrade_component::UpgradableInternalImpl,
    };
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_protocol, assert_only_self},
        calls::{execute_multicall, execute_multicall_with_result}, serialization::full_deserialize,
        transaction_version::{assert_correct_deploy_account_version, assert_correct_invoke_version},
    };
    use openzeppelin_security::reentrancyguard::{ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl};
    use starknet::storage::StoragePointerReadAccess;
    use starknet::{ClassHash, VALIDATED, account::Call, get_contract_address, get_execution_info, get_tx_info};

    const NAME: felt252 = 'ArgentMultisig';
    const VERSION: Version = Version { major: 0, minor: 3, patch: 0 };

    // Signer Management
    component!(path: signer_manager_component, storage: signer_manager, event: SignerManagerEvents);
    #[abi(embed_v0)]
    impl SignerManager = signer_manager_component::SignerManagerImpl<ContractState>;
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
    // Upgrade migration
    component!(path: upgrade_migration_component, storage: upgrade_migration, event: UpgradeMigrationEvents);
    // External Recovery
    component!(path: external_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ToggleExternalRecovery = external_recovery_component::ExternalRecoveryImpl<ContractState>;
    // Reentrancy guard
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_manager: signer_manager_component::Storage,
        #[substorage(v0)]
        execute_from_outside: outside_execution_component::Storage,
        #[substorage(v0)]
        src5: src5_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
        #[substorage(v0)]
        upgrade_migration: upgrade_migration_component::Storage,
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
        ExecuteFromOutsideEvents: outside_execution_component::Event,
        #[flat]
        SRC5Events: src5_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
        #[flat]
        UpgradeMigrationEvents: upgrade_migration_component::Event,
        #[flat]
        EscapeEvents: external_recovery_component::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        TransactionExecuted: TransactionExecuted,
    }

    /// Deprecated: This event will likely be removed in the future
    /// @notice Emitted when the account executes a transaction
    /// @param hash The transaction hash
    #[derive(Drop, starknet::Event)]
    struct TransactionExecuted {
        #[key]
        hash: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, threshold: usize, signers: Array<Signer>) {
        self.signer_manager.initialize(threshold, signers);
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let exec_info = get_execution_info();
            let tx_info = exec_info.tx_info;
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            assert(tx_info.account_deployment_data.is_empty(), 'argent/invalid-deployment-data');
            self.assert_valid_calls(calls.span());
            self.assert_valid_signatures(tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) {
            self.reentrancy_guard.start();
            let exec_info = get_execution_info();
            let tx_info = exec_info.tx_info;
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);

            // execute calls
            execute_multicall(calls.span());
            // emit event
            let hash = tx_info.transaction_hash;
            self.emit(TransactionExecuted { hash });
            self.reentrancy_guard.end();
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            if self
                .signer_manager
                .is_valid_signature_with_threshold(
                    hash,
                    self.signer_manager.threshold.read(),
                    signer_signatures: parse_signature_array(signature.span()),
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
            core::panic_with_felt252('argent/declare-not-available') // Not implemented yet
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            threshold: usize,
            signers: Array<Signer>,
        ) -> felt252 {
            let tx_info = get_tx_info();
            assert_correct_deploy_account_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            // only 1 signer needed to deploy
            let is_valid = self
                .signer_manager
                .is_valid_signature_with_threshold(
                    tx_info.transaction_hash, threshold: 1, signer_signatures: parse_signature_array(tx_info.signature),
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
            self.assert_valid_signatures(outside_execution_hash, signature);

            let retdata = execute_multicall_with_result(calls);
            self.emit(TransactionExecuted { hash: outside_execution_hash });
            retdata
        }
    }

    impl IExternalRecoveryCallbackImpl of IExternalRecoveryCallback<ContractState> {
        #[inline(always)]
        fn execute_recovery_call(ref self: ContractState, selector: felt252, calldata: Span<felt252>) {
            let calls = array![Call { to: get_contract_address(), selector, calldata }].span();
            self.assert_valid_calls(calls);
            execute_multicall(calls);
            self.emit(TransactionExecuted { hash: get_tx_info().transaction_hash });
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        // Called when coming from multisig 0.1.X
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();
            self.upgrade_migration.migrate_from_before_0_2_0();
            assert(data.len() == 0, 'argent/unexpected-data');
            array![]
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        // Called when coming from multisig 0.2.0 and above
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            assert_only_self();

            // Downgrade check
            let argent_dispatcher = IArgentAccountDispatcher { contract_address: get_contract_address() };
            assert(argent_dispatcher.get_name() == self.get_name(), 'argent/invalid-name');
            let previous_version = argent_dispatcher.get_version();
            let current_version = self.get_version();
            assert(previous_version < current_version, 'argent/downgrade-not-allowed');

            self.upgrade.complete_upgrade(new_implementation);

            self.upgrade_migration.migrate_from_0_2_0();

            assert(data.len() == 0, 'argent/unexpected-data');
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
                // Make sure no call is to the account. We don't have any good reason to perform many calls to the
                // account in the same transactions and this restriction will reduce the attack surface
                assert_no_self_call(calls, account_address);
            }
        }

        fn assert_valid_signatures(self: @ContractState, execution_hash: felt252, signature: Span<felt252>) {
            let valid = self
                .signer_manager
                .is_valid_signature_with_threshold(
                    execution_hash,
                    self.signer_manager.threshold.read(),
                    signer_signatures: parse_signature_array(signature),
                );
            assert(valid, 'argent/invalid-signature');
        }
    }

    #[must_use]
    #[inline(always)]
    fn parse_signature_array(mut raw_signature: Span<felt252>) -> Array<SignerSignature> {
        full_deserialize(raw_signature).expect('argent/invalid-signature-format')
    }
}

