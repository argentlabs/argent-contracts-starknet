#[starknet::contract(account)]
pub mod ArgentAccount {
    use argent::account::interface::{IAccount, IDeprecatedArgentAccount, IEmitArgentAccountEvent, Version};
    use argent::introspection::src5::src5_component;
    use argent::multiowner_account::account_interface::{
        IArgentMultiOwnerAccount, IArgentMultiOwnerAccountDispatcher, IArgentMultiOwnerAccountDispatcherTrait,
        OwnerAliveSignature,
    };
    use argent::multiowner_account::events::{
        AccountCreated, AccountCreatedGuid, EscapeCanceled, EscapeGuardianTriggeredGuid, EscapeOwnerTriggeredGuid,
        EscapeSecurityPeriodChanged, GuardianEscapedGuid, OwnerEscapedGuid, SignerLinked, TransactionExecuted,
    };
    use argent::multiowner_account::guardian_manager::{
        IGuardianManager, guardian_manager_component, guardian_manager_component::GuardianManagerInternalImpl,
    };
    use argent::multiowner_account::owner_alive::OwnerAlive;
    use argent::multiowner_account::owner_manager::{
        owner_manager_component, owner_manager_component::OwnerManagerInternalImpl,
    };
    use argent::multiowner_account::recovery::{Escape, EscapeType};
    use argent::multiowner_account::upgrade_migration::{
        IUpgradeMigrationCallback, IUpgradeMigrationInternal, upgrade_migration_component,
        upgrade_migration_component::UpgradeMigrationInternalImpl,
    };

    use argent::offchain_message::interface::IOffChainMessageHashRev1;
    use argent::outside_execution::{
        interface::IOutsideExecutionCallback, outside_execution::outside_execution_component,
    };
    use argent::recovery::EscapeStatus;
    use argent::session::{interface::ISessionCallback, session::{session_component, session_component::InternalTrait}};
    use argent::signer::signer_signature::{
        Signer, SignerSignature, SignerSignatureTrait, SignerStorageTrait, SignerStorageValue, SignerTrait, SignerType,
        StarknetSignature, StarknetSigner,
    };
    use argent::upgrade::{
        interface::{IUpgradableCallback, IUpgradableCallbackOld},
        upgrade::{IUpgradeInternal, upgrade_component, upgrade_component::UpgradableInternalImpl},
    };
    use argent::utils::array_ext::SpanContains;
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_protocol, assert_only_self},
        calls::{execute_multicall, execute_multicall_with_result}, serialization::{full_deserialize, serialize},
        transaction_version::{
            DA_MODE_L1, TX_V1, TX_V1_ESTIMATE, TX_V3, TX_V3_ESTIMATE, assert_correct_declare_version,
            assert_correct_deploy_account_version, assert_correct_invoke_version,
        },
    };
    use core::panic_with_felt252;
    use openzeppelin_security::reentrancyguard::{ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl};
    use starknet::{
        ClassHash, ContractAddress, VALIDATED, account::Call, get_block_timestamp, get_contract_address,
        get_execution_info, get_tx_info, storage::{StoragePointerReadAccess, StoragePointerWriteAccess},
    };

    const NAME: felt252 = 'ArgentAccount';
    const VERSION: Version = Version { major: 0, minor: 5, patch: 0 };
    const VERSION_COMPAT: felt252 = '0.5.0';

    /// Time it takes for the escape to become ready after being triggered. Also the escape will be
    /// ready and can be completed for this duration
    const DEFAULT_ESCAPE_SECURITY_PERIOD: u64 = 7 * 24 * 60 * 60; // 7 days

    /// Limit to one escape every X hours
    const TIME_BETWEEN_TWO_ESCAPES: u64 = 12 * 60 * 60; // 12 hours;

    /// Limits fee in escapes
    const MAX_ESCAPE_MAX_FEE_ETH: u128 = 5000000000000000; // 0.005 ETH
    const MAX_ESCAPE_MAX_FEE_STRK: u128 = 5_000000000000000000; // 5 STRK
    const MAX_ESCAPE_TIP_STRK: u128 = 1_000000000000000000; // 1 STRK

    /// Minimum time for the escape security period
    const MIN_ESCAPE_SECURITY_PERIOD: u64 = 60 * 10; // 10 minutes;
    /// Maximum time the change owner message should be valid for
    const ONE_DAY: u64 = 60 * 60 * 24;


    // Owner management
    component!(path: owner_manager_component, storage: owner_manager, event: OwnerManagerEvents);
    #[abi(embed_v0)]
    impl OwnerManager = owner_manager_component::OwnerManagerImpl<ContractState>;
    // Guardian management
    component!(path: guardian_manager_component, storage: guardian_manager, event: GuardianManagerEvents);
    #[abi(embed_v0)]
    impl GuardianManager = guardian_manager_component::GuardianManagerImpl<ContractState>;
    // session
    component!(path: session_component, storage: session, event: SessionableEvents);
    #[abi(embed_v0)]
    impl Sessionable = session_component::SessionImpl<ContractState>;
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
    #[abi(embed_v0)]
    impl FixStorage = upgrade_migration_component::RecoveryFromLegacyUpgradeImpl<ContractState>;
    // Reentrancy guard
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        owner_manager: owner_manager_component::Storage,
        #[substorage(v0)]
        guardian_manager: guardian_manager_component::Storage,
        #[substorage(v0)]
        execute_from_outside: outside_execution_component::Storage,
        #[substorage(v0)]
        src5: src5_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
        #[substorage(v0)]
        upgrade_migration: upgrade_migration_component::Storage,
        #[substorage(v0)]
        session: session_component::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        /// The ongoing escape, if any
        #[allow(starknet::colliding_storage_paths)]
        _escape: Escape,
        /// The following 4 fields are used to limit the number of escapes the account will pay for
        /// Values are Rounded down to the hour:
        /// https://community.starknet.io/t/starknet-v0-13-1-pre-release-notes/113664 Values are
        /// resets when an escape is completed or canceled
        last_guardian_trigger_escape_attempt: u64,
        last_owner_trigger_escape_attempt: u64,
        last_guardian_escape_attempt: u64,
        last_owner_escape_attempt: u64,
        escape_security_period: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnerManagerEvents: owner_manager_component::Event,
        #[flat]
        GuardianManagerEvents: guardian_manager_component::Event,
        #[flat]
        ExecuteFromOutsideEvents: outside_execution_component::Event,
        #[flat]
        SRC5Events: src5_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
        #[flat]
        UpgradeMigrationEvents: upgrade_migration_component::Event,
        #[flat]
        SessionableEvents: session_component::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        TransactionExecuted: TransactionExecuted,
        AccountCreated: AccountCreated,
        AccountCreatedGuid: AccountCreatedGuid,
        EscapeOwnerTriggeredGuid: EscapeOwnerTriggeredGuid,
        EscapeGuardianTriggeredGuid: EscapeGuardianTriggeredGuid,
        OwnerEscapedGuid: OwnerEscapedGuid,
        GuardianEscapedGuid: GuardianEscapedGuid,
        EscapeCanceled: EscapeCanceled,
        SignerLinked: SignerLinked,
        EscapeSecurityPeriodChanged: EscapeSecurityPeriodChanged,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: Signer, guardian: Option<Signer>) {
        let owner_guid = self.owner_manager.initialize(owner);
        let guardian_guid_or_zero = if let Option::Some(guardian) = guardian {
            self.guardian_manager.initialize(guardian)
        } else {
            0
        };

        if let Option::Some(starknet_owner) = owner.starknet_pubkey_or_none() {
            if let Option::Some(guardian) = guardian {
                if let Option::Some(starknet_guardian) = guardian.starknet_pubkey_or_none() {
                    self.emit(AccountCreated { owner: starknet_owner, guardian: starknet_guardian });
                };
            } else {
                self.emit(AccountCreated { owner: starknet_owner, guardian: 0 });
            };
        };
        self.emit(AccountCreatedGuid { owner_guid, guardian_guid: guardian_guid_or_zero });
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let exec_info = get_execution_info();
            let tx_info = exec_info.tx_info;
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            if self.session.is_session(tx_info.signature) {
                self.session.assert_valid_session(calls.span(), tx_info.transaction_hash, tx_info.signature);
            } else {
                self
                    .assert_valid_calls_and_signature(
                        calls.span(),
                        tx_info.transaction_hash,
                        tx_info.signature,
                        is_from_outside: false,
                        account_address: exec_info.contract_address,
                    );
            }
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) {
            self.reentrancy_guard.start();
            let exec_info = get_execution_info();
            let tx_info = exec_info.tx_info;
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);
            let signature = tx_info.signature;
            if self.session.is_session(signature) {
                let session_timestamp = *signature[1];
                // can call unwrap safely as the session has already been deserialized
                let session_timestamp_u64 = session_timestamp.try_into().unwrap();
                assert(session_timestamp_u64 >= exec_info.block_info.block_timestamp, 'session/expired');
            }

            execute_multicall(calls.span());

            self.emit(TransactionExecuted { hash: tx_info.transaction_hash });
            self.reentrancy_guard.end();
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            if self.is_valid_span_signature(hash, self.parse_signature_array(signature.span()).span()) {
                VALIDATED
            } else {
                0
            }
        }
    }

    // Required Callbacks
    impl EmitArgentAccountEventImpl of IEmitArgentAccountEvent<ContractState> {
        fn emit_event_callback(ref self: ContractState, event: Event) {
            self.emit(event);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        // Called when coming from account v0.2.3 to v0.3.1. Note that accounts v0.2.3.* won't always call this method
        // But v0.3.0+ is guaranteed to call it
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            self.upgrade_migration.migrate_from_before_0_4_0();

            if data.is_empty() {
                return array![];
            }

            let calls: Array<Call> = full_deserialize(data.span()).expect('argent/invalid-calls');
            assert_no_self_call(calls.span(), get_contract_address());

            serialize(@execute_multicall_with_result(calls.span()))
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        // Called when coming from account 0.4.0+
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            assert_only_self();

            // Downgrade check
            let argent_dispatcher = IArgentMultiOwnerAccountDispatcher { contract_address: get_contract_address() };
            assert(argent_dispatcher.get_name() == self.get_name(), 'argent/invalid-name');
            let previous_version = argent_dispatcher.get_version();
            let current_version = self.get_version();
            assert(previous_version < current_version, 'argent/downgrade-not-allowed');

            self.upgrade.complete_upgrade(new_implementation);

            self.upgrade_migration.migrate_from_0_4_0();

            if data.is_empty() {
                return;
            }

            let calls: Array<Call> = full_deserialize(data).expect('argent/invalid-calls');
            assert_no_self_call(calls.span(), get_contract_address());
            execute_multicall(calls.span());
        }
    }

    impl UpgradeMigrationCallbackImpl of IUpgradeMigrationCallback<ContractState> {
        fn finalize_migration(ref self: ContractState) {
            self.owner_manager.assert_valid_storage();
            self.guardian_manager.assert_valid_storage();

            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn migrate_owner(ref self: ContractState, signer_storage_value: SignerStorageValue) {
            self.owner_manager.initialize_from_upgrade(signer_storage_value);
        }

        fn migrate_guardians(ref self: ContractState, guardians_storage_value: Array<SignerStorageValue>) {
            self.guardian_manager.migrate_guardians_storage(guardians_storage_value);
        }
    }

    impl OutsideExecutionCallbackImpl of IOutsideExecutionCallback<ContractState> {
        #[inline(always)]
        fn execute_from_outside_callback(
            ref self: ContractState, calls: Span<Call>, outside_execution_hash: felt252, signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            if self.session.is_session(signature) {
                self.session.assert_valid_session(calls, outside_execution_hash, signature);
            } else {
                self
                    .assert_valid_calls_and_signature(
                        calls,
                        outside_execution_hash,
                        signature,
                        is_from_outside: true,
                        account_address: get_contract_address(),
                    );
            }
            let retdata = execute_multicall_with_result(calls);
            self.emit(TransactionExecuted { hash: outside_execution_hash });
            retdata
        }
    }


    impl SessionCallbackImpl of ISessionCallback<ContractState> {
        fn validate_authorization(
            self: @ContractState, session_hash: felt252, authorization_signature: Span<felt252>,
        ) -> Array<SignerSignature> {
            let parsed_authorization = self.parse_signature_array(authorization_signature);
            assert(
                self.is_valid_span_signature(session_hash, parsed_authorization.span()), 'session/invalid-account-sig',
            );
            parsed_authorization
        }

        fn is_owner_guid(self: @ContractState, owner_guid: felt252) -> bool {
            self.owner_manager.is_owner_guid(owner_guid)
        }

        fn is_guardian_guid(self: @ContractState, guardian_guid: felt252) -> bool {
            self.guardian_manager.is_guardian_guid(guardian_guid)
        }
    }

    #[abi(embed_v0)]
    impl ArgentMultiOwnerAccountImpl of IArgentMultiOwnerAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let tx_info = get_tx_info();
            assert_correct_declare_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            self
                .assert_valid_span_signature(
                    tx_info.transaction_hash, self.parse_signature_array(tx_info.signature).span(),
                );
            VALIDATED
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: Signer,
            guardian: Option<Signer>,
        ) -> felt252 {
            let tx_info = get_tx_info();
            assert_correct_deploy_account_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            self
                .assert_valid_span_signature(
                    tx_info.transaction_hash, self.parse_signature_array(tx_info.signature).span(),
                );
            VALIDATED
        }

        fn set_escape_security_period(ref self: ContractState, new_security_period: u64) {
            assert_only_self();
            assert(new_security_period >= MIN_ESCAPE_SECURITY_PERIOD, 'argent/invalid-security-period');

            let current_escape = self._escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at);
            match current_escape_status {
                EscapeStatus::None => (), // ignore
                EscapeStatus::NotReady | EscapeStatus::Ready => panic_with_felt252('argent/ongoing-escape'),
                EscapeStatus::Expired => self._escape.write(Default::default()),
            }
            self.escape_security_period.write(new_security_period);
            self.emit(EscapeSecurityPeriodChanged { escape_security_period: new_security_period });
        }

        fn get_escape_security_period(self: @ContractState) -> u64 {
            let storage_value = self.escape_security_period.read();
            if storage_value == 0 {
                DEFAULT_ESCAPE_SECURITY_PERIOD
            } else {
                storage_value
            }
        }


        fn change_owners(
            ref self: ContractState,
            owner_guids_to_remove: Array<felt252>,
            owners_to_add: Array<Signer>,
            owner_alive_signature: Option<OwnerAliveSignature>,
        ) {
            assert_only_self();
            self.owner_manager.change_owners(owner_guids_to_remove, owners_to_add);

            if let Option::Some(owner_alive_signature) = owner_alive_signature {
                self.assert_valid_owner_alive_signature(owner_alive_signature);
            } // else { validation will ensure it's not needed }

            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn change_guardians(
            ref self: ContractState, guardian_guids_to_remove: Array<felt252>, guardians_to_add: Array<Signer>,
        ) {
            assert_only_self();
            self.guardian_manager.change_guardians(:guardian_guids_to_remove, :guardians_to_add);
            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn trigger_escape_owner(ref self: ContractState, new_owner: Signer) {
            assert_only_self();

            // no escape if there is a guardian escape triggered by the owner in progress
            let current_escape = self._escape.read();
            if current_escape.escape_type == EscapeType::Guardian {
                assert(
                    self.get_escape_status(current_escape.ready_at) == EscapeStatus::Expired,
                    'argent/cannot-override-escape',
                );
            }

            self.reset_escape();
            let ready_at = get_block_timestamp() + self.get_escape_security_period();
            let escape = Escape {
                ready_at, escape_type: EscapeType::Owner, new_signer: Option::Some(new_owner.storage_value()),
            };
            self._escape.write(escape);

            let new_owner_guid = new_owner.into_guid();

            self.emit(EscapeOwnerTriggeredGuid { ready_at, new_owner_guid: new_owner_guid });
            self.emit(SignerLinked { signer_guid: new_owner_guid, signer: new_owner });
        }

        fn trigger_escape_guardian(ref self: ContractState, new_guardian: Option<Signer>) {
            assert_only_self();

            self.reset_escape();
            let (new_guardian_guid, new_guardian_storage_value) = if let Option::Some(guardian) = new_guardian {
                let guardian_guid = guardian.into_guid();
                self.emit(SignerLinked { signer_guid: guardian_guid, signer: guardian });
                (guardian_guid, Option::Some(guardian.storage_value()))
            } else {
                (0, Option::None)
            };

            let ready_at = get_block_timestamp() + self.get_escape_security_period();
            let escape = Escape { ready_at, escape_type: EscapeType::Guardian, new_signer: new_guardian_storage_value };
            self._escape.write(escape);
            self.emit(EscapeGuardianTriggeredGuid { ready_at, new_guardian_guid });
        }

        fn escape_owner(ref self: ContractState) {
            assert_only_self();

            // assert_valid_calls_and_signature(...) guarantees that the escape is of the correct type
            let current_escape = self._escape.read();

            let current_escape_status = self.get_escape_status(current_escape.ready_at);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            self.reset_escape_timestamps();

            // update owner
            let new_owner = current_escape.new_signer.unwrap();
            self.owner_manager.complete_owner_escape(new_owner);
            self.emit(OwnerEscapedGuid { new_owner_guid: new_owner.into_guid() });

            // clear escape
            self._escape.write(Default::default());
        }

        fn escape_guardian(ref self: ContractState) {
            assert_only_self();

            // assert_valid_calls_and_signature(...) guarantees that the escape is of the correct type
            let current_escape = self._escape.read();
            assert(self.get_escape_status(current_escape.ready_at) == EscapeStatus::Ready, 'argent/invalid-escape');

            self.reset_escape_timestamps();

            let new_guardian = current_escape.new_signer;
            self.guardian_manager.complete_guardian_escape(new_guardian);
            if let Option::Some(new_guardian) = new_guardian {
                self.emit(GuardianEscapedGuid { new_guardian_guid: new_guardian.into_guid() });
            } else {
                self.emit(GuardianEscapedGuid { new_guardian_guid: 0 });
            }

            // clear escape
            self._escape.write(Default::default());
        }

        fn cancel_escape(ref self: ContractState) {
            assert_only_self();
            let current_escape = self._escape.read();
            let current_escape_status = self.get_escape_status(current_escape.ready_at);
            assert(current_escape_status != EscapeStatus::None, 'argent/invalid-escape');
            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn get_escape(self: @ContractState) -> Escape {
            self._escape.read()
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            VERSION
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        fn get_last_owner_trigger_escape_attempt(self: @ContractState) -> u64 {
            self.last_owner_trigger_escape_attempt.read()
        }

        fn get_last_guardian_trigger_escape_attempt(self: @ContractState) -> u64 {
            self.last_guardian_trigger_escape_attempt.read()
        }

        fn get_last_guardian_escape_attempt(self: @ContractState) -> u64 {
            self.last_guardian_escape_attempt.read()
        }

        fn get_last_owner_escape_attempt(self: @ContractState) -> u64 {
            self.last_owner_escape_attempt.read()
        }

        /// Current escape if any, and its status
        fn get_escape_and_status(self: @ContractState) -> (Escape, EscapeStatus) {
            let current_escape = self._escape.read();
            (current_escape, self.get_escape_status(current_escape.ready_at))
        }
    }

    #[abi(embed_v0)]
    impl DeprecatedArgentAccountImpl of IDeprecatedArgentAccount<ContractState> {
        fn getVersion(self: @ContractState) -> felt252 {
            VERSION_COMPAT
        }

        fn getName(self: @ContractState) -> felt252 {
            self.get_name()
        }

        fn isValidSignature(self: @ContractState, hash: felt252, signatures: Array<felt252>) -> felt252 {
            assert(self.is_valid_signature(hash, signatures) == VALIDATED, 'argent/invalid-signature');
            1
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls_and_signature(
            ref self: ContractState,
            calls: Span<Call>,
            execution_hash: felt252,
            mut signatures: Span<felt252>,
            is_from_outside: bool,
            account_address: ContractAddress,
        ) {
            if calls.len() == 1 {
                let call = calls.at(0);
                if *call.to == account_address {
                    let selector = *call.selector;

                    if selector == selector!("trigger_escape_owner") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_guardian_trigger_escape_attempt.read());
                            self.last_guardian_trigger_escape_attempt.write(get_block_timestamp());
                        }

                        let new_owner = full_deserialize::<Signer>(*call.calldata).expect('argent/invalid-calldata');
                        assert(!self.is_owner(new_owner), 'argent/invalid-owner-replace'); // TODO is this needed?
                        let guardian_signature = self.parse_single_guardian_signature(signatures);
                        let is_valid = self.is_valid_guardian_signature(execution_hash, guardian_signature);
                        assert(is_valid, 'argent/invalid-guardian-sig');
                        // valid guardian signature also asserts that a guardian is set
                        return; // valid
                    }
                    if selector == selector!("escape_owner") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_guardian_escape_attempt.read());
                            self.last_guardian_escape_attempt.write(get_block_timestamp());
                        }

                        assert((*call.calldata).is_empty(), 'argent/invalid-calldata');
                        let current_escape = self._escape.read();
                        assert(current_escape.escape_type == EscapeType::Owner, 'argent/invalid-escape');
                        let guardian_signature = self.parse_single_guardian_signature(signatures);
                        let is_valid = self.is_valid_guardian_signature(execution_hash, guardian_signature);
                        assert(is_valid, 'argent/invalid-guardian-sig');
                        // valid guardian signature also asserts that a guardian is set
                        return; // valid
                    }
                    if selector == selector!("trigger_escape_guardian") {
                        self.assert_guardian_set();

                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_owner_trigger_escape_attempt.read());
                            self.last_owner_trigger_escape_attempt.write(get_block_timestamp());
                        }

                        let _ = full_deserialize::<Option<Signer>>(*call.calldata).expect('argent/invalid-calldata');

                        let owner_signature = self.parse_single_owner_signature(signatures);
                        let is_valid = self.is_valid_owner_signature(execution_hash, owner_signature);
                        assert(is_valid, 'argent/invalid-owner-sig');
                        return; // valid
                    }
                    if selector == selector!("escape_guardian") {
                        self.assert_guardian_set();

                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_owner_escape_attempt.read());
                            self.last_owner_escape_attempt.write(get_block_timestamp());
                        }
                        assert((*call.calldata).is_empty(), 'argent/invalid-calldata');
                        let current_escape = self._escape.read();

                        assert(current_escape.escape_type == EscapeType::Guardian, 'argent/invalid-escape');

                        let owner_signature = self.parse_single_owner_signature(signatures);
                        let is_valid = self.is_valid_owner_signature(execution_hash, owner_signature);
                        assert(is_valid, 'argent/invalid-owner-sig');
                        return; // valid
                    }
                    if selector == selector!("change_owners") {
                        let signer_signatures: Array<SignerSignature> = self.parse_signature_array(signatures);
                        if !self.has_guardian() {
                            let (owner_guids_to_remove, _, owner_alive_signature) = full_deserialize::<
                                (Array<felt252>, Array<Signer>, Option<OwnerAliveSignature>),
                            >(*call.calldata)
                                .expect('argent/invalid-calldata');

                            let signer_still_valid = !owner_guids_to_remove
                                .span()
                                .contains((*signer_signatures[0]).signer().into_guid());

                            assert(signer_still_valid || owner_alive_signature.is_some(), 'argent/missing-owner-alive');
                        }
                        self.assert_valid_span_signature(execution_hash, signer_signatures.span());
                        return; // valid
                    }
                    assert(selector != selector!("execute_after_upgrade"), 'argent/forbidden-call');
                    assert(selector != selector!("perform_upgrade"), 'argent/forbidden-call');
                }
            } else {
                // make sure no call is to the account
                assert_no_self_call(calls, account_address);
            }
            let signer_signatures: Array<SignerSignature> = self.parse_signature_array(signatures);
            self.assert_valid_span_signature(execution_hash, signer_signatures.span());
        }

        // TODO This was the most straight forward to remove to not exceed contract size limit
        // We prob want to re-assess
        // #[inline(always)]
        fn parse_signature_array(self: @ContractState, mut signatures: Span<felt252>) -> Array<SignerSignature> {
            // Check if it's a legacy signature array, this only supports legacy signature if there is exactly 1 only
            // and a maximum of 1 guardian Legacy signatures are always 2 or 4 items long
            // Shortest signature in modern format is at least 5 items
            //  [array_len, signer_type, signer_pubkey, r, s]
            if signatures.len() != 2 && signatures.len() != 4 {
                // manual inlining instead of calling full_deserialize for performance
                let deserialized: Array<SignerSignature> = Serde::deserialize(ref signatures)
                    .expect('argent/invalid-signature-format');
                assert(signatures.is_empty(), 'argent/invalid-signature-length');
                return deserialized;
            }

            let single_stark_owner = self
                .owner_manager
                .get_single_stark_owner_pubkey()
                .expect('argent/no-single-stark-owner');
            let owner_signature = SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: single_stark_owner.try_into().expect('argent/zero-pubkey') },
                    StarknetSignature { r: *signatures.pop_front().unwrap(), s: *signatures.pop_front().unwrap() },
                ),
            );
            if signatures.is_empty() {
                return array![owner_signature];
            }

            let single_stark_guardian = self
                .guardian_manager
                .get_single_stark_guardian_pubkey()
                .expect('argent/no-single-guardian-owner');

            let guardian_signature = SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: single_stark_guardian.try_into().expect('argent/zero-pubkey') },
                    StarknetSignature { r: *signatures.pop_front().unwrap(), s: *signatures.pop_front().unwrap() },
                ),
            );
            return array![owner_signature, guardian_signature];
        }

        /// Parses the signature when its expected to be a single owner signature
        fn parse_single_owner_signature(self: @ContractState, mut signatures: Span<felt252>) -> SignerSignature {
            if signatures.len() != 2 {
                let signature_array: Array<SignerSignature> = full_deserialize(signatures)
                    .expect('argent/invalid-signature-format');
                assert(signature_array.len() == 1, 'argent/invalid-signature-length');
                return *signature_array.at(0);
            }
            let single_stark_owner = self
                .owner_manager
                .get_single_stark_owner_pubkey()
                .expect('argent/no-single-stark-owner');
            SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: single_stark_owner.try_into().expect('argent/zero-pubkey') },
                    StarknetSignature { r: *signatures.pop_front().unwrap(), s: *signatures.pop_front().unwrap() },
                ),
            )
        }

        /// Parses the signature when its expected to be a single guardian signature
        fn parse_single_guardian_signature(self: @ContractState, mut signatures: Span<felt252>) -> SignerSignature {
            if signatures.len() != 2 {
                let signature_array: Array<SignerSignature> = full_deserialize(signatures)
                    .expect('argent/invalid-signature-format');
                assert(signature_array.len() == 1, 'argent/invalid-signature-length');
                return *signature_array.at(0);
            }
            let single_stark_guardian = self
                .guardian_manager
                .get_single_stark_guardian_pubkey()
                .expect('argent/no-single-guardian-owner');
            return SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: single_stark_guardian.try_into().expect('argent/zero-pubkey') },
                    StarknetSignature { r: *signatures.pop_front().unwrap(), s: *signatures.pop_front().unwrap() },
                ),
            );
        }

        #[must_use]
        fn is_valid_span_signature(
            self: @ContractState, hash: felt252, signer_signatures: Span<SignerSignature>,
        ) -> bool {
            if self.has_guardian() {
                assert(signer_signatures.len() == 2, 'argent/invalid-signature-length');
                self.is_valid_owner_signature(hash, *signer_signatures.at(0))
                    && self.is_valid_guardian_signature(hash, *signer_signatures.at(1))
            } else {
                assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                self.is_valid_owner_signature(hash, *signer_signatures.at(0))
            }
        }

        fn assert_valid_span_signature(self: @ContractState, hash: felt252, signer_signatures: Span<SignerSignature>) {
            if self.has_guardian() {
                assert(signer_signatures.len() == 2, 'argent/invalid-signature-length');
                assert(self.is_valid_owner_signature(hash, *signer_signatures.at(0)), 'argent/invalid-owner-sig');
                assert(self.is_valid_guardian_signature(hash, *signer_signatures.at(1)), 'argent/invalid-guardian-sig');
            } else {
                assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                assert(self.is_valid_owner_signature(hash, *signer_signatures.at(0)), 'argent/invalid-owner-sig');
            }
        }

        /// The message hash is the result of hashing the SNIP-12 compliant object OwnerAlive
        fn assert_valid_owner_alive_signature(self: @ContractState, owner_alive_signature: OwnerAliveSignature) {
            let signature_expiration = owner_alive_signature.signature_expiration;
            let owner_signature = owner_alive_signature.owner_signature;
            assert(signature_expiration >= get_block_timestamp(), 'argent/expired-signature');
            assert(signature_expiration - get_block_timestamp() <= ONE_DAY, 'argent/timestamp-too-far-future');
            let new_owner_guid = owner_signature.signer().into_guid();
            assert(self.owner_manager.is_owner_guid(new_owner_guid), 'argent/invalid-sig-not-owner');
            let message_hash = OwnerAlive { new_owner_guid, signature_expiration }.get_message_hash_rev_1();
            let is_valid = owner_signature.is_valid_signature(message_hash);
            assert(is_valid, 'argent/invalid-alive-sig');
        }

        fn get_escape_status(self: @ContractState, escape_ready_at: u64) -> EscapeStatus {
            if escape_ready_at == 0 {
                return EscapeStatus::None;
            }

            let block_timestamp = get_block_timestamp();
            if block_timestamp < escape_ready_at {
                return EscapeStatus::NotReady;
            }
            if escape_ready_at + self.get_escape_security_period() <= block_timestamp {
                return EscapeStatus::Expired;
            }

            EscapeStatus::Ready
        }

        fn reset_escape(ref self: ContractState) {
            let current_escape_status = self.get_escape_status(self._escape.read().ready_at);
            if current_escape_status == EscapeStatus::None {
                return;
            }
            self._escape.write(Default::default());
            if current_escape_status != EscapeStatus::Expired {
                self.emit(EscapeCanceled {});
            }
        }

        fn assert_guardian_set(self: @ContractState) {
            assert(self.has_guardian(), 'argent/guardian-required');
        }

        fn reset_escape_timestamps(ref self: ContractState) {
            self.last_owner_trigger_escape_attempt.write(0);
            self.last_guardian_trigger_escape_attempt.write(0);
            self.last_owner_escape_attempt.write(0);
            self.last_guardian_escape_attempt.write(0);
        }
    }

    fn assert_valid_escape_parameters(last_timestamp: u64) {
        let mut tx_info = get_tx_info().unbox();
        if tx_info.version == TX_V3 || tx_info.version == TX_V3_ESTIMATE {
            // No need for modes other than L1 while escaping
            assert(
                tx_info.nonce_data_availability_mode == DA_MODE_L1 && tx_info.fee_data_availability_mode == DA_MODE_L1,
                'argent/invalid-da-mode',
            );

            // No need to allow self deployment and escaping in one transaction
            assert(tx_info.account_deployment_data.is_empty(), 'argent/invalid-deployment-data');

            // Limit the maximum tip and maximum total fee while escaping
            let mut max_fee: u128 = 0;
            let mut max_tip: u128 = 0;
            loop {
                match tx_info.resource_bounds.pop_front() {
                    Option::Some(bound) => {
                        let max_resource_amount: u128 = (*bound.max_amount).into();
                        max_fee += *bound.max_price_per_unit * max_resource_amount;
                        if *bound.resource == 'L2_GAS' {
                            max_tip += tx_info.tip * max_resource_amount;
                        }
                    },
                    Option::None => { break; },
                };
            };
            max_fee += max_tip;
            assert(max_tip <= MAX_ESCAPE_TIP_STRK, 'argent/tip-too-high');
            assert(max_fee <= MAX_ESCAPE_MAX_FEE_STRK, 'argent/max-fee-too-high');
        } else if tx_info.version == TX_V1 || tx_info.version == TX_V1_ESTIMATE {
            // other fields not available on V1
            assert(tx_info.max_fee <= MAX_ESCAPE_MAX_FEE_ETH, 'argent/max-fee-too-high');
        } else {
            panic_with_felt252('argent/invalid-tx-version');
        }

        assert(get_block_timestamp() > last_timestamp + TIME_BETWEEN_TWO_ESCAPES, 'argent/last-escape-too-recent');
    }

    fn guardian_ordered_types() -> Span<SignerType> {
        array![
            SignerType::Starknet,
            SignerType::Eip191,
            SignerType::Webauthn,
            SignerType::Secp256r1,
            SignerType::Secp256k1,
        ]
            .span()
    }
}
