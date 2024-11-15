#[starknet::contract(account)]
mod ArgentAccount {
    use argent::account::interface::{IAccount, IArgentAccount, IDeprecatedArgentAccount, Version};
    use argent::introspection::src5::src5_component;
    use argent::multiowner_account::account_interface::{
        IArgentMultiOwnerAccount, IArgentMultiOwnerAccountDispatcher, IArgentMultiOwnerAccountDispatcherTrait
    };
    use argent::multiowner_account::events::{
        SignerLinked, TransactionExecuted, AccountCreated, AccountCreatedGuid, EscapeOwnerTriggeredGuid,
        EscapeGuardianTriggeredGuid, OwnerEscapedGuid, GuardianEscapedGuid, EscapeCanceled, OwnerChanged,
        OwnerChangedGuid, GuardianChanged, GuardianChangedGuid, GuardianBackupChanged, GuardianBackupChangedGuid,
        EscapeSecurityPeriodChanged,
    };
    use argent::multiowner_account::owner_manager::{IOwnerManager, IOwnerManagerCallback, owner_manager_component};
    use argent::multiowner_account::recovery::{LegacyEscape, LegacyEscapeType};
    use argent::multiowner_account::replace_owners_message::ReplaceOwnersWithOne;
    use argent::offchain_message::interface::IOffChainMessageHashRev1;
    use argent::outside_execution::{
        outside_execution::outside_execution_component, interface::{IOutsideExecutionCallback}
    };
    use argent::recovery::EscapeStatus;

    use argent::session::{
        interface::ISessionCallback, session::{session_component::{Internal, InternalTrait}, session_component}
    };
    use argent::signer::{
        signer_signature::{
            Signer, SignerStorageValue, SignerType, StarknetSigner, StarknetSignature, SignerTrait, SignerStorageTrait,
            SignerSignature, SignerSignatureTrait, starknet_signer_from_pubkey
        }
    };
    use argent::upgrade::{
        upgrade::{IUpgradeInternal, upgrade_component}, interface::{IUpgradableCallback, IUpgradableCallbackOld}
    };
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_self, assert_only_protocol}, calls::execute_multicall,
        serialization::full_deserialize,
        transaction_version::{
            TX_V1, TX_V1_ESTIMATE, TX_V3, TX_V3_ESTIMATE, assert_correct_invoke_version, assert_correct_declare_version,
            assert_correct_deploy_account_version, DA_MODE_L1, is_estimate_transaction
        }
    };
    use hash::{HashStateTrait, HashStateExTrait};
    use openzeppelin_security::reentrancyguard::ReentrancyGuardComponent;
    use pedersen::PedersenTrait;
    use starknet::{
        storage::Map, ContractAddress, ClassHash, get_block_timestamp, get_contract_address, VALIDATED, account::Call,
        SyscallResultTrait, get_tx_info, get_execution_info, replace_class_syscall,
        storage_access::{
            storage_read_syscall, storage_address_from_base_and_offset, storage_base_address_from_felt252,
            storage_write_syscall
        }
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
    impl OwnerManagerInternal = owner_manager_component::OwnerManagerInternalImpl<ContractState>;
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
    impl UpgradableInternal = upgrade_component::UpgradableInternalImpl<ContractState>;
    // Reentrancy guard
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        owner_manager: owner_manager_component::Storage,
        #[substorage(v0)]
        execute_from_outside: outside_execution_component::Storage,
        #[substorage(v0)]
        src5: src5_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
        #[substorage(v0)]
        session: session_component::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        /// Current account guardian
        _guardian: felt252,
        /// Current account backup guardian
        _guardian_backup: felt252,
        _guardian_backup_non_stark: Map<felt252, felt252>,
        /// The ongoing escape, if any
        _escape: LegacyEscape,
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
    enum Event {
        #[flat]
        OwnerManagerEvents: owner_manager_component::Event,
        #[flat]
        ExecuteFromOutsideEvents: outside_execution_component::Event,
        #[flat]
        SRC5Events: src5_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
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
        OwnerChanged: OwnerChanged,
        OwnerChangedGuid: OwnerChangedGuid,
        GuardianChanged: GuardianChanged,
        GuardianChangedGuid: GuardianChangedGuid,
        GuardianBackupChanged: GuardianBackupChanged,
        GuardianBackupChangedGuid: GuardianBackupChangedGuid,
        SignerLinked: SignerLinked,
        EscapeSecurityPeriodChanged: EscapeSecurityPeriodChanged,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: Signer, guardian: Option<Signer>) {
        self.owner_manager.initialize(owner);
        let owner_guid = owner.into_guid();
        self.emit(SignerLinked { signer_guid: owner_guid, signer: owner });
        if let Option::Some(guardian) = guardian {
            let guardian_storage_value = guardian.storage_value();
            assert(guardian_storage_value.signer_type == SignerType::Starknet, 'argent/invalid-guardian-type');
            self._guardian.write(guardian_storage_value.stored_value);
            let guardian_guid = guardian_storage_value.into_guid();
            self.emit(SignerLinked { signer_guid: guardian_guid, signer: guardian });
        };
        // TODO: AccountCreated events
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
                self.session.assert_valid_session(calls.span(), tx_info.transaction_hash, tx_info.signature,);
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

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
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

            let retdata = execute_multicall(calls.span());

            self.emit(TransactionExecuted { hash: tx_info.transaction_hash, response: retdata.span() });
            self.reentrancy_guard.end();
            retdata
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
    impl OwnerManagerCallbackImpl of IOwnerManagerCallback<ContractState> {
        fn emit_signer_linked_event(ref self: ContractState, event: SignerLinked) {
            self.emit(event);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        // Called when coming from account v0.2.3 to v0.3.1. Note that accounts v0.2.3.* won't always call this method
        // But v0.3.0+ is guaranteed to call it
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();
            self.migrate_from_before_0_4_0();

            if data.is_empty() {
                return array![];
            }

            let calls: Array<Call> = full_deserialize(data.span()).expect('argent/invalid-calls');
            assert_no_self_call(calls.span(), get_contract_address());

            let multicall_return = execute_multicall(calls.span());
            let mut output = array![];
            multicall_return.serialize(ref output);
            output
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        // Called when coming from account 0.4.0+
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            assert_only_self();
            self.migrate_from_0_4_0();

            self.upgrade.complete_upgrade(new_implementation);

            if data.is_empty() {
                return;
            }

            let calls: Array<Call> = full_deserialize(data).expect('argent/invalid-calls');
            assert_no_self_call(calls.span(), get_contract_address());
            execute_multicall(calls.span());
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
                        account_address: get_contract_address()
                    );
            }
            let retdata = execute_multicall(calls);
            self.emit(TransactionExecuted { hash: outside_execution_hash, response: retdata.span() });
            retdata
        }
    }


    impl SessionCallbackImpl of ISessionCallback<ContractState> {
        fn parse_authorization(self: @ContractState, authorization_signature: Span<felt252>) -> Array<SignerSignature> {
            self.parse_signature_array(authorization_signature)
        }
        fn assert_valid_authorization(
            self: @ContractState, session_hash: felt252, authorization_signature: Span<SignerSignature>
        ) {
            assert(self.is_valid_span_signature(session_hash, authorization_signature), 'session/invalid-account-sig')
        }
        fn get_guardian_guid_callback(self: @ContractState) -> Option<felt252> {
            self.get_guardian_guid()
        }
        fn is_owner_guid(self: @ContractState, owner_guid: felt252) -> bool {
            self.owner_manager.is_owner_guid(owner_guid)
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
                    tx_info.transaction_hash, self.parse_signature_array(tx_info.signature).span()
                );
            VALIDATED
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: Signer,
            guardian: Option<Signer>
        ) -> felt252 {
            let tx_info = get_tx_info();
            assert_correct_deploy_account_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            self
                .assert_valid_span_signature(
                    tx_info.transaction_hash, self.parse_signature_array(tx_info.signature).span()
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

        fn add_owners(ref self: ContractState, new_owners: Array<Signer>) {
            assert_only_self();
            self.owner_manager.add_owners(new_owners);
            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn remove_owners(ref self: ContractState, owner_guids_to_remove: Array<felt252>) {
            assert_only_self();
            // during __validate__ we assert that the owner is not removing itself and therefore that you can't remove
            // all owners
            self.owner_manager.remove_owners(owner_guids_to_remove);
            // Reset the escape as we have signatures from both the owner and the guardian
            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn replace_all_owners_with_one(
            ref self: ContractState, new_single_owner: SignerSignature, signature_expiration: u64
        ) {
            assert_only_self();
            let new_owner = new_single_owner.signer();
            self.assert_valid_new_owner_signature(new_single_owner, signature_expiration);
            // This already emits OwnerRemovedGuid & OwnerAddedGuid events
            self.owner_manager.replace_all_owners_with_one(new_owner.storage_value());

            if let Option::Some(new_owner_pubkey) = new_owner.storage_value().starknet_pubkey_or_none() {
                self.emit(OwnerChanged { new_owner: new_owner_pubkey });
            };
            // TODO Check events w/ backend
            let new_owner_guid = new_owner.into_guid();
            self.emit(OwnerChangedGuid { new_owner_guid });
            self.emit(SignerLinked { signer_guid: new_owner_guid, signer: new_owner });

            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn change_guardian(ref self: ContractState, new_guardian: Option<Signer>) {
            assert_only_self();

            if let Option::Some(guardian) = new_guardian {
                let guardian_storage_value = guardian.storage_value();
                assert(guardian_storage_value.signer_type == SignerType::Starknet, 'argent/invalid-guardian-type');
                let new_guardian_guid = guardian_storage_value.into_guid();
                self.write_guardian(Option::Some(guardian_storage_value));
                self.emit(SignerLinked { signer_guid: new_guardian_guid, signer: guardian });
                self.emit(GuardianChanged { new_guardian: guardian_storage_value.stored_value });
                self.emit(GuardianChangedGuid { new_guardian_guid });
            } else {
                // There cannot be a guardian_backup when there is no guardian
                assert(self.read_guardian_backup().is_none(), 'argent/backup-should-be-null');
                self.write_guardian(Option::None);
                self.emit(GuardianChanged { new_guardian: 0 });
                self.emit(GuardianChangedGuid { new_guardian_guid: 0 });
            }
            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn change_guardian_backup(ref self: ContractState, new_guardian_backup: Option<Signer>) {
            assert_only_self();
            self.assert_guardian_set();
            if let Option::Some(guardian) = new_guardian_backup {
                let guardian_storage_value = guardian.storage_value();
                let new_guardian_guid = guardian_storage_value.into_guid();
                self.write_guardian_backup(Option::Some(guardian.storage_value()));
                self.emit(SignerLinked { signer_guid: new_guardian_guid, signer: guardian });
                if let Option::Some(guardian_pubkey) = guardian_storage_value.starknet_pubkey_or_none() {
                    self.emit(GuardianBackupChanged { new_guardian_backup: guardian_pubkey });
                };
                self.emit(GuardianBackupChangedGuid { new_guardian_backup_guid: new_guardian_guid });
            } else {
                self.write_guardian_backup(Option::None);
                self.emit(GuardianBackupChanged { new_guardian_backup: 0 });
                self.emit(GuardianBackupChangedGuid { new_guardian_backup_guid: 0 });
            };

            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn trigger_escape_owner(ref self: ContractState, new_owner: Signer) {
            assert_only_self();

            // no escape if there is a guardian escape triggered by the owner in progress
            let current_escape = self._escape.read();
            if current_escape.escape_type == LegacyEscapeType::Guardian {
                assert(
                    self.get_escape_status(current_escape.ready_at) == EscapeStatus::Expired,
                    'argent/cannot-override-escape'
                );
            }

            self.reset_escape();
            let ready_at = get_block_timestamp() + self.get_escape_security_period();
            let escape = LegacyEscape {
                ready_at, escape_type: LegacyEscapeType::Owner, new_signer: Option::Some(new_owner.storage_value()),
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
            let escape = LegacyEscape {
                ready_at, escape_type: LegacyEscapeType::Guardian, new_signer: new_guardian_storage_value,
            };
            self._escape.write(escape);
            self.emit(EscapeGuardianTriggeredGuid { ready_at, new_guardian_guid });
        }

        fn escape_owner(ref self: ContractState) {
            assert_only_self();

            let current_escape = self._escape.read();

            let current_escape_status = self.get_escape_status(current_escape.ready_at);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            self.reset_escape_timestamps();

            // update owner
            let new_owner = current_escape.new_signer.unwrap();
            self.owner_manager.replace_all_owners_with_one(new_owner);
            self.emit(OwnerEscapedGuid { new_owner_guid: new_owner.into_guid() });

            // clear escape
            self._escape.write(Default::default());
        }

        fn escape_guardian(ref self: ContractState) {
            assert_only_self();

            let current_escape = self._escape.read();
            assert(self.get_escape_status(current_escape.ready_at) == EscapeStatus::Ready, 'argent/invalid-escape');

            self.reset_escape_timestamps();

            self.write_guardian(current_escape.new_signer);
            if let Option::Some(guardian) = current_escape.new_signer {
                self.emit(GuardianEscapedGuid { new_guardian_guid: guardian.into_guid() });
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

        fn get_owner(self: @ContractState) -> felt252 {
            let owner = self.owner_manager.get_single_owner().expect('argent/no-single-owner');
            assert(!owner.is_stored_as_guid(), 'argent/only_guid');
            owner.stored_value
        }

        fn get_owner_type(self: @ContractState) -> SignerType {
            self.owner_manager.get_single_owner().expect('argent/no-single-owner').signer_type
        }

        fn get_owner_guid(self: @ContractState) -> felt252 {
            self.owner_manager.get_single_owner().expect('argent/no-single-owner').into_guid()
        }

        fn get_guardian(self: @ContractState) -> felt252 {
            match self.read_guardian() {
                Option::Some(guardian) => {
                    assert(!guardian.is_stored_as_guid(), 'argent/only_guid');
                    guardian.stored_value
                },
                Option::None => 0,
            }
        }

        fn get_guardian_type(self: @ContractState) -> Option<SignerType> {
            match self.read_guardian() {
                Option::Some(guardian) => Option::Some(guardian.signer_type),
                Option::None => Option::None,
            }
        }

        fn is_guardian(self: @ContractState, guardian: Signer) -> bool {
            self.is_valid_guardian(guardian.storage_value())
        }

        fn get_guardian_guid(self: @ContractState) -> Option<felt252> {
            match self.read_guardian() {
                Option::Some(guardian) => Option::Some(guardian.into_guid()),
                Option::None => Option::None,
            }
        }

        fn get_guardian_backup(self: @ContractState) -> felt252 {
            match self.read_guardian_backup() {
                Option::Some(guardian_backup) => {
                    assert(!guardian_backup.is_stored_as_guid(), 'argent/only_guid');
                    guardian_backup.stored_value
                },
                Option::None => 0,
            }
        }

        fn get_guardian_backup_type(self: @ContractState) -> Option<SignerType> {
            match self.read_guardian_backup() {
                Option::Some(guardian_backup) => Option::Some(guardian_backup.signer_type),
                Option::None => Option::None,
            }
        }

        fn get_guardian_backup_guid(self: @ContractState) -> Option<felt252> {
            match self.read_guardian_backup() {
                Option::Some(guardian_backup) => Option::Some(guardian_backup.into_guid()),
                Option::None => Option::None,
            }
        }

        fn get_escape(self: @ContractState) -> LegacyEscape {
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
        fn get_escape_and_status(self: @ContractState) -> (LegacyEscape, EscapeStatus) {
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

                        let new_signer = full_deserialize::<Signer>(*call.calldata).expect('argent/invalid-calldata');
                        self.owner_manager.is_valid_owners_replacement(new_signer);
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
                        assert(current_escape.escape_type == LegacyEscapeType::Owner, 'argent/invalid-escape');
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

                        let new_guardian: Option<Signer> = full_deserialize(*call.calldata)
                            .expect('argent/invalid-calldata');

                        if let Option::Some(new_guardian) = new_guardian {
                            assert(new_guardian.signer_type() == SignerType::Starknet, 'argent/invalid-guardian-type');
                        } else {
                            assert(self.read_guardian_backup().is_none(), 'argent/backup-should-be-null');
                        }

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

                        assert(current_escape.escape_type == LegacyEscapeType::Guardian, 'argent/invalid-escape');

                        let owner_signature = self.parse_single_owner_signature(signatures);
                        let is_valid = self.is_valid_owner_signature(execution_hash, owner_signature);
                        assert(is_valid, 'argent/invalid-owner-sig');
                        return; // valid
                    }

                    if selector == selector!("remove_owners") {
                        // guarantees that the owner is not removing itself and therefore that you can't remove all
                        // owners
                        let owner_guids_to_remove: Array<felt252> = full_deserialize(*call.calldata)
                            .expect('argent/invalid-calldata');
                        let signer_signatures: Array<SignerSignature> = self.parse_signature_array(signatures);
                        let signature_owner_guid = (*signer_signatures[0]).signer().into_guid();
                        for owner_guid_to_remove in owner_guids_to_remove {
                            assert(owner_guid_to_remove != signature_owner_guid, 'argent/cant-remove-self');
                        };
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

        fn migrate_from_before_0_4_0(ref self: ContractState) {
            // As the storage layout for the escape is changing, if there is an ongoing escape it should revert
            // Expired escapes will be cleared
            let escape_base = storage_base_address_from_felt252(selector!("_escape"));
            let escape_ready_at = storage_read_syscall(0, storage_address_from_base_and_offset(escape_base, 0))
                .unwrap_syscall();

            if escape_ready_at == 0 {
                let escape_type = storage_read_syscall(0, storage_address_from_base_and_offset(escape_base, 1))
                    .unwrap_syscall();
                let escape_new_signer = storage_read_syscall(0, storage_address_from_base_and_offset(escape_base, 2))
                    .unwrap_syscall();
                assert(escape_type.is_zero(), 'argent/esc-type-not-null');
                assert(escape_new_signer.is_zero(), 'argent/esc-new-signer-not-null');
            } else {
                let escape_ready_at: u64 = escape_ready_at.try_into().unwrap();
                if get_block_timestamp() < escape_ready_at + DEFAULT_ESCAPE_SECURITY_PERIOD {
                    // Not expired. Automatically cancelling the escape when upgrading
                    self.emit(EscapeCanceled {});
                }
                // Clear the escape
                self._escape.write(Default::default());
            }

            // Cleaning attempts storage as the escape was cleared
            let guardian_escape_attempts_storage_address = selector!("guardian_escape_attempts").try_into().unwrap();
            storage_write_syscall(0, guardian_escape_attempts_storage_address, 0).unwrap_syscall();
            let owner_escape_attempts_storage_address = selector!("owner_escape_attempts").try_into().unwrap();
            storage_write_syscall(0, owner_escape_attempts_storage_address, 0).unwrap_syscall();

            // Check basic invariants and emit missing events
            let owner_key_storage_address = selector!("_signer").try_into().unwrap();
            let owner_key = storage_read_syscall(0, owner_key_storage_address).unwrap_syscall();
            let guardian_key = self._guardian.read();
            let guardian_backup_key = self._guardian_backup.read();
            assert(owner_key != 0, 'argent/null-owner');
            if guardian_key == 0 {
                assert(guardian_backup_key == 0, 'argent/backup-should-be-null');
            } else {
                let guardian = starknet_signer_from_pubkey(guardian_key);
                self.emit(SignerLinked { signer_guid: guardian.into_guid(), signer: guardian });
                if guardian_backup_key != 0 {
                    let guardian_backup = starknet_signer_from_pubkey(guardian_backup_key);
                    self.emit(SignerLinked { signer_guid: guardian_backup.into_guid(), signer: guardian_backup });
                }
            }

            let owner = starknet_signer_from_pubkey(owner_key);
            self.emit(SignerLinked { signer_guid: owner.into_guid(), signer: owner });

            let implementation_storage_address = selector!("_implementation").try_into().unwrap();
            let implementation = storage_read_syscall(0, implementation_storage_address).unwrap_syscall();

            if implementation != Zeroable::zero() {
                replace_class_syscall(implementation.try_into().unwrap()).expect('argent/invalid-after-upgrade');
                storage_write_syscall(0, implementation_storage_address, 0).unwrap_syscall();
            }

            self.migrate_from_0_4_0();
        }

        fn migrate_from_0_4_0(ref self: ContractState) {
            // TODO remove proxy slots?
            let signer_storage_address = selector!("_signer").try_into().unwrap();
            let signer_to_migrate = storage_read_syscall(0, signer_storage_address).unwrap_syscall();
            // As we come from a version that has a _signer slot
            // If it is 0, it means we are migrating from an account that is already at the current version
            assert(signer_to_migrate != 0, 'argent/downgrade-not-allowed');
            let stark_signer = starknet_signer_from_pubkey(signer_to_migrate);
            self.owner_manager.initialize(stark_signer);
            // Reset _signer storage
            storage_write_syscall(0, signer_storage_address, 0).unwrap_syscall();

            // Health check
            // Should we check if _signer_non_stark is empty?
            let guardian_key = self._guardian.read();
            let guardian_backup_key = self._guardian_backup.read();
            if guardian_key == 0 {
                assert(guardian_backup_key == 0, 'argent/backup-should-be-null');
            }

            self.reset_escape();
            self.reset_escape_timestamps();
        }

        #[inline(always)]
        fn parse_signature_array(self: @ContractState, mut signatures: Span<felt252>) -> Array<SignerSignature> {
            // Check if it's a legacy signature array (there's no support for guardian backup)
            // Legacy signatures are always 2 or 4 items long
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
                    StarknetSignature { r: *signatures.pop_front().unwrap(), s: *signatures.pop_front().unwrap() }
                )
            );
            if signatures.is_empty() {
                return array![owner_signature];
            }

            let guardian_signature = SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: self._guardian.read().try_into().expect('argent/zero-pubkey') },
                    StarknetSignature { r: *signatures.pop_front().unwrap(), s: *signatures.pop_front().unwrap() }
                )
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
                    StarknetSignature { r: *signatures.pop_front().unwrap(), s: *signatures.pop_front().unwrap() }
                )
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
            return SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: self._guardian.read().try_into().expect('argent/guardian-not-set') },
                    StarknetSignature { r: *signatures.pop_front().unwrap(), s: *signatures.pop_front().unwrap() }
                )
            );
        }

        #[must_use]
        fn is_valid_span_signature(
            self: @ContractState, hash: felt252, signer_signatures: Span<SignerSignature>
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

        #[must_use]
        fn is_valid_guardian_signature(self: @ContractState, hash: felt252, signer_signature: SignerSignature) -> bool {
            let signer = signer_signature.signer().storage_value();
            if !self.is_valid_guardian(signer) && !self.is_valid_guardian_backup(signer) {
                return false;
            }
            return signer_signature.is_valid_signature(hash) || is_estimate_transaction();
        }

        /// The message hash is the result of hashing the SNIP-12 compliant object ReplaceOwnersWithOne
        fn assert_valid_new_owner_signature(
            self: @ContractState, new_single_owner: SignerSignature, signature_expiration: u64
        ) {
            assert(signature_expiration >= get_block_timestamp(), 'argent/expired-signature');
            assert(signature_expiration - get_block_timestamp() <= ONE_DAY, 'argent/timestamp-too-far-future');
            let new_owner_guid = new_single_owner.signer().into_guid();
            let message_hash = ReplaceOwnersWithOne { new_owner_guid, signature_expiration }.get_message_hash_rev_1();
            let is_valid = new_single_owner.is_valid_signature(message_hash);
            assert(is_valid, 'argent/invalid-new-owner-sig');
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

        #[inline(always)]
        fn assert_guardian_set(self: @ContractState) {
            assert(self.read_guardian().is_some(), 'argent/guardian-required');
        }

        #[inline(always)]
        fn reset_escape_timestamps(ref self: ContractState) {
            self.last_owner_trigger_escape_attempt.write(0);
            self.last_guardian_trigger_escape_attempt.write(0);
            self.last_owner_escape_attempt.write(0);
            self.last_guardian_escape_attempt.write(0);
        }

        fn write_guardian(ref self: ContractState, guardian: Option<SignerStorageValue>) {
            // clear storage
            if let Option::Some(old_guardian) = self.read_guardian() {
                assert(old_guardian.signer_type == SignerType::Starknet, 'argent/invalid-guardian-type');
                self._guardian.write(0);
            }
            // write storage
            if let Option::Some(guardian) = guardian {
                assert(guardian.signer_type == SignerType::Starknet, 'argent/invalid-guardian-type');
                self._guardian.write(guardian.stored_value);
            }
        }

        fn read_guardian(self: @ContractState) -> Option<SignerStorageValue> {
            // Guardian is restricted to Starknet Key
            let guardian_stored_value = self._guardian.read();
            if guardian_stored_value == 0 {
                Option::None
            } else {
                Option::Some(
                    SignerStorageValue { stored_value: guardian_stored_value, signer_type: SignerType::Starknet }
                )
            }
        }

        #[inline(always)]
        fn has_guardian(self: @ContractState) -> bool {
            // Guardian is restricted to Starknet Key
            self._guardian.read() != 0
        }

        #[inline(always)]
        fn is_valid_guardian(self: @ContractState, guardian: SignerStorageValue) -> bool {
            match guardian.signer_type {
                SignerType::Starknet => (self._guardian.read() == guardian.stored_value),
                _ => false
            }
        }

        fn write_guardian_backup(ref self: ContractState, guardian_backup: Option<SignerStorageValue>) {
            // clear storage
            if let Option::Some(old_guardian_backup) = self.read_guardian_backup() {
                match old_guardian_backup.signer_type {
                    SignerType::Starknet => self._guardian_backup.write(0),
                    _ => self._guardian_backup_non_stark.write(old_guardian_backup.signer_type.into(), 0),
                }
            };
            // write storage
            if let Option::Some(guardian_backup) = guardian_backup {
                match guardian_backup.signer_type {
                    SignerType::Starknet => self._guardian_backup.write(guardian_backup.stored_value),
                    _ => self
                        ._guardian_backup_non_stark
                        .write(guardian_backup.signer_type.into(), guardian_backup.stored_value),
                }
            }
        }

        fn read_guardian_backup(self: @ContractState) -> Option<SignerStorageValue> {
            let mut preferred_order = guardian_ordered_types();
            loop {
                let signer_type = match preferred_order.pop_front() {
                    Option::Some(signer_type) => *signer_type,
                    Option::None => { break Option::None; },
                };
                let guardian_backup_guid = match signer_type {
                    SignerType::Starknet => self._guardian_backup.read(),
                    _ => self._guardian_backup_non_stark.read(signer_type.into()),
                };
                if guardian_backup_guid != 0 {
                    break Option::Some(
                        SignerStorageValue { stored_value: guardian_backup_guid.try_into().unwrap(), signer_type }
                    );
                }
            }
        }

        #[inline(always)]
        fn is_valid_guardian_backup(self: @ContractState, guardian_backup: SignerStorageValue) -> bool {
            match guardian_backup.signer_type {
                SignerType::Starknet => (self._guardian_backup.read() == guardian_backup.stored_value),
                _ => (self
                    ._guardian_backup_non_stark
                    .read(guardian_backup.signer_type.into()) == guardian_backup
                    .stored_value
                    .into())
            }
        }
    }

    fn assert_valid_escape_parameters(last_timestamp: u64) {
        let mut tx_info = get_tx_info().unbox();
        if tx_info.version == TX_V3 || tx_info.version == TX_V3_ESTIMATE {
            // No need for modes other than L1 while escaping
            assert(
                tx_info.nonce_data_availability_mode == DA_MODE_L1 && tx_info.fee_data_availability_mode == DA_MODE_L1,
                'argent/invalid-da-mode'
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
                    Option::None => { break; }
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
            SignerType::Starknet, SignerType::Eip191, SignerType::Webauthn, SignerType::Secp256r1, SignerType::Secp256k1
        ]
            .span()
    }
}
