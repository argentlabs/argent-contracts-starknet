#[starknet::contract(account)]
mod ArgentAccount {
    use argent::account::interface::{IAccount, IArgentAccount, IArgentUserAccount, IDeprecatedArgentAccount, Version};
    use argent::introspection::src5::src5_component;
    use argent::outside_execution::{
        outside_execution::outside_execution_component, interface::{IOutsideExecutionCallback}
    };
    use argent::recovery::interface::{LegacyEscape, LegacyEscapeType, EscapeStatus};
    use argent::session::{
        interface::{SessionToken, ISessionCallback},
        session::{session_component::{Internal, InternalTrait}, session_component,}
    };
    use argent::signer::{
        signer_signature::{
            Signer, SignerStorageValue, SignerType, StarknetSigner, StarknetSignature, SignerTrait, SignerStorageTrait,
            SignerSignature, SignerSignatureTrait, starknet_signer_from_pubkey
        }
    };
    use argent::upgrade::{upgrade::upgrade_component, interface::{IUpgradableCallback, IUpgradableCallbackOld}};
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_self, assert_only_protocol}, calls::execute_multicall,
        serialization::full_deserialize,
        transaction_version::{
            TX_V1, TX_V1_ESTIMATE, TX_V3, TX_V3_ESTIMATE, assert_correct_invoke_version, assert_correct_declare_version,
            assert_correct_deploy_account_version, DA_MODE_L1, is_estimate_transaction
        }
    };
    use hash::HashStateTrait;
    use pedersen::PedersenTrait;
    use starknet::{
        ContractAddress, ClassHash, get_block_timestamp, get_contract_address, VALIDATED, replace_class_syscall,
        account::Call, SyscallResultTrait, get_tx_info, get_execution_info, syscalls::storage_read_syscall,
        storage_access::{storage_address_from_base_and_offset, storage_base_address_from_felt252, storage_write_syscall}
    };

    const NAME: felt252 = 'ArgentAccount';
    const VERSION: Version = Version { major: 0, minor: 4, patch: 0 };
    const VERSION_COMPAT: felt252 = '0.4.0';

    /// Time it takes for the escape to become ready after being triggered. Also the escape will be ready and can be completed for this duration
    const DEFAULT_ESCAPE_SECURITY_PERIOD: u64 = consteval_int!(7 * 24 * 60 * 60); // 7 days

    /// Limit to one escape every X hours
    const TIME_BETWEEN_TWO_ESCAPES: u64 = consteval_int!(12 * 60 * 60); // 12 hours;

    /// Limits fee in escapes
    const MAX_ESCAPE_MAX_FEE_ETH: u128 = 5000000000000000; // 0.005 ETH
    const MAX_ESCAPE_MAX_FEE_STRK: u128 = 5_000000000000000000; // 5 STRK
    const MAX_ESCAPE_TIP_STRK: u128 = 1_000000000000000000; // 1 STRK

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

    #[storage]
    struct Storage {
        #[substorage(v0)]
        execute_from_outside: outside_execution_component::Storage,
        #[substorage(v0)]
        src5: src5_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
        #[substorage(v0)]
        session: session_component::Storage,
        _implementation: ClassHash, // This is deprecated and used to migrate cairo 0 accounts only
        /// Current account owner
        _signer: felt252,
        _signer_non_stark: LegacyMap<felt252, felt252>,
        /// Current account guardian
        _guardian: felt252,
        /// Current account backup guardian
        _guardian_backup: felt252,
        _guardian_backup_non_stark: LegacyMap<felt252, felt252>,
        /// The ongoing escape, if any
        _escape: LegacyEscape,
        /// Keeps track of the last time an escape was performed by the guardian.
        /// Rounded down to the hour: https://community.starknet.io/t/starknet-v0-13-1-pre-release-notes/113664 
        /// Used to limit the number of escapes the account will pay for
        /// It resets when an escape is completed or canceled
        last_guardian_escape_attempt: u64,
        /// Keeps track of the last time an escape was performed by the owner. 
        /// Rounded down to the hour: https://community.starknet.io/t/starknet-v0-13-1-pre-release-notes/113664 
        /// Used to limit the number of transactions the account will pay for
        /// It resets when an escape is completed or canceled
        last_owner_escape_attempt: u64,
        escape_security_period: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ExecuteFromOutsideEvents: outside_execution_component::Event,
        #[flat]
        SRC5Events: src5_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
        #[flat]
        SessionableEvents: session_component::Event,
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

    /// @notice Deprecated. This is only emitted for the owner and then guardian when they of type SignerType::Starknet
    /// @dev Emitted exactly once when the account is initialized
    /// @param owner The owner starknet pubkey
    /// @param guardian The guardian starknet pubkey or 0 if there's no guardian
    #[derive(Drop, starknet::Event)]
    struct AccountCreated {
        #[key]
        owner: felt252,
        guardian: felt252
    }

    /// @notice Emitted on initialization with the guids of the owner and the guardian (or 0 if none) 
    /// @dev Emitted exactly once when the account is initialized
    /// @param owner The owner guid
    /// @param guardian The guardian guid or 0 if there's no guardian
    #[derive(Drop, starknet::Event)]
    struct AccountCreatedGuid {
        #[key]
        owner_guid: felt252,
        guardian_guid: felt252
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

    /// @notice Owner escape was triggered by the guardian
    /// @param ready_at when the escape can be completed
    /// @param new_owner_guid new guid to be set after the security period
    #[derive(Drop, starknet::Event)]
    struct EscapeOwnerTriggeredGuid {
        ready_at: u64,
        new_owner_guid: felt252
    }

    /// @notice Guardian escape was triggered by the owner
    /// @param ready_at when the escape can be completed
    /// @param new_guardian_guid to be set after the security period. O if the guardian will be removed
    #[derive(Drop, starknet::Event)]
    struct EscapeGuardianTriggeredGuid {
        ready_at: u64,
        new_guardian_guid: felt252
    }

    /// @notice Owner escape was completed and there is a new account owner
    /// @param new_owner_guid new owner guid
    #[derive(Drop, starknet::Event)]
    struct OwnerEscapedGuid {
        new_owner_guid: felt252
    }

    /// @notice Guardian escape was completed and there is a new account guardian
    /// @param new_guardian_guid guid of the new guardian or 0 if it was removed
    #[derive(Drop, starknet::Event)]
    struct GuardianEscapedGuid {
        new_guardian_guid: felt252
    }

    /// @notice An ongoing escape was canceled
    #[derive(Drop, starknet::Event)]
    struct EscapeCanceled {}

    /// @notice Deprecated from v0.4.0. This is only emitted if the new owner is a starknet key
    /// @notice The account owner was changed
    /// @param new_owner new owner address
    #[derive(Drop, starknet::Event)]
    struct OwnerChanged {
        new_owner: felt252
    }

    /// @notice The account owner was changed
    /// @param new_owner_guid new owner guid
    #[derive(Drop, starknet::Event)]
    struct OwnerChangedGuid {
        new_owner_guid: felt252
    }

    /// @notice Deprecated from v0.4.0. This is only emitted if the new guardian is empty or a starknet key
    /// @notice The account guardian was changed or removed
    /// @param new_guardian address of the new guardian or 0 if it was removed
    #[derive(Drop, starknet::Event)]
    struct GuardianChanged {
        new_guardian: felt252
    }

    /// @notice The account guardian was changed or removed
    /// @param new_guardian_guid address of the new guardian or 0 if it was removed
    #[derive(Drop, starknet::Event)]
    struct GuardianChangedGuid {
        new_guardian_guid: felt252
    }

    /// @notice Deprecated from v0.4.0. This is only emitted if the new guardian backup is empty or a starknet key
    /// @notice The account backup guardian was changed or removed
    /// @param new_guardian_backup address of the backup guardian or 0 if it was removed
    #[derive(Drop, starknet::Event)]
    struct GuardianBackupChanged {
        new_guardian_backup: felt252
    }

    /// @notice The account backup guardian was changed or removed
    /// @param new_guardian_backup_guid guid of the backup guardian or 0 if it was removed
    #[derive(Drop, starknet::Event)]
    struct GuardianBackupChangedGuid {
        new_guardian_backup_guid: felt252
    }

    /// @notice A new signer was linked 
    /// @dev This is the only way to get the signer struct knowing a only guid
    /// @param signer_guid the guid of the signer derived from the signer
    /// @param signer the signer being added 
    #[derive(Drop, starknet::Event)]
    struct SignerLinked {
        #[key]
        signer_guid: felt252,
        signer: Signer,
    }

    /// @notice The security period for the escape was update
    /// @param escape_security_period the new security for the escape in seconds
    #[derive(Drop, starknet::Event)]
    struct EscapeSecurityPeriodChanged {
        escape_security_period: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: Signer, guardian: Option<Signer>) {
        let owner_storage_value = owner.storage_value();
        let owner_guid = owner_storage_value.into_guid();
        self.init_owner(owner_storage_value);
        self.emit(SignerLinked { signer_guid: owner_guid, signer: owner });

        let guardian_guid: felt252 = if let Option::Some(guardian) = guardian {
            let guardian_storage_value = guardian.storage_value();
            assert(guardian_storage_value.signer_type == SignerType::Starknet, 'argent/invalid-guardian-type');
            self._guardian.write(guardian_storage_value.stored_value);
            let guardian_guid = guardian_storage_value.into_guid();
            self.emit(SignerLinked { signer_guid: guardian_guid, signer: guardian });
            if owner_storage_value.signer_type == SignerType::Starknet {
                self
                    .emit(
                        AccountCreated {
                            owner: owner_storage_value.stored_value, guardian: guardian_storage_value.stored_value
                        }
                    );
            };
            guardian_guid
        } else {
            if owner_storage_value.signer_type == SignerType::Starknet {
                self.emit(AccountCreated { owner: owner_storage_value.stored_value, guardian: 0 });
            };
            0
        };

        self.emit(AccountCreatedGuid { owner_guid, guardian_guid });
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let exec_info = get_execution_info().unbox();
            let tx_info = exec_info.tx_info.unbox();
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
            let exec_info = get_execution_info().unbox();
            let tx_info = exec_info.tx_info.unbox();
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);
            let signature = tx_info.signature;
            if self.session.is_session(signature) {
                let session_timestamp = *signature[1];
                // can call unwrap safely as the session has already been deserialized 
                let session_timestamp_u64 = session_timestamp.try_into().unwrap();
                assert(session_timestamp_u64 >= exec_info.block_info.unbox().block_timestamp, 'session/expired');
            }

            let retdata = execute_multicall(calls.span());

            self.emit(TransactionExecuted { hash: tx_info.transaction_hash, response: retdata.span() });
            retdata
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            if self.is_valid_span_signature(hash, self.parse_signature_array(signature.span())) {
                VALIDATED
            } else {
                0
            }
        }
    }

    // Required Callbacks

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        // Called when coming from account 0.3.1 or older
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            // As the storage layout for the escape is changing, if there is an ongoing escape it should revert
            // Expired escapes will be cleared
            let base = storage_base_address_from_felt252(selector!("_escape"));
            let escape_ready_at = storage_read_syscall(0, storage_address_from_base_and_offset(base, 0))
                .unwrap_syscall();

            if escape_ready_at == 0 {
                let escape_type = storage_read_syscall(0, storage_address_from_base_and_offset(base, 1))
                    .unwrap_syscall();
                let escape_new_signer = storage_read_syscall(0, storage_address_from_base_and_offset(base, 2))
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
            let base = storage_base_address_from_felt252(selector!("guardian_escape_attempts"));
            storage_write_syscall(0, storage_address_from_base_and_offset(base, 0), 0).unwrap_syscall();
            let base = storage_base_address_from_felt252(selector!("owner_escape_attempts"));
            storage_write_syscall(0, storage_address_from_base_and_offset(base, 0), 0).unwrap_syscall();

            // Check basic invariants and emit missing events
            let owner_key = self._signer.read();
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

            let implementation = self._implementation.read();
            if implementation != Zeroable::zero() {
                replace_class_syscall(implementation).expect('argent/invalid-after-upgrade');
                self._implementation.write(Zeroable::zero());
            }

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
            panic_with_felt252('argent/downgrade-not-allowed');
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
        fn session_callback(
            self: @ContractState, session_hash: felt252, authorization_signature: Span<felt252>
        ) -> bool {
            self.is_valid_span_signature(session_hash, self.parse_signature_array(authorization_signature))
        }
    }


    #[abi(embed_v0)]
    impl ArgentUserAccountImpl of IArgentUserAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let tx_info = get_tx_info().unbox();
            assert_correct_declare_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            self.assert_valid_span_signature(tx_info.transaction_hash, self.parse_signature_array(tx_info.signature));
            VALIDATED
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: Signer,
            guardian: Option<Signer>
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            assert_correct_deploy_account_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            self.assert_valid_span_signature(tx_info.transaction_hash, self.parse_signature_array(tx_info.signature));
            VALIDATED
        }

        fn set_escape_security_period(ref self: ContractState, new_security_period: u64) {
            assert_only_self();
            assert(new_security_period != 0, 'argent/invalid-security-period');
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

        fn change_owner(ref self: ContractState, signer_signature: SignerSignature) {
            assert_only_self();

            let new_owner = signer_signature.signer();

            self.assert_valid_new_owner_signature(signer_signature);

            let new_owner_storage_value = new_owner.storage_value();
            self.write_owner(new_owner_storage_value);

            if let Option::Some(new_owner_pubkey) = new_owner_storage_value.starknet_pubkey_or_none() {
                self.emit(OwnerChanged { new_owner: new_owner_pubkey });
            };
            let new_owner_guid = new_owner_storage_value.into_guid();
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
            self.write_owner(new_owner);
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
            let owner = self.read_owner();
            assert(!owner.is_stored_as_guid(), 'argent/only_guid');
            owner.stored_value
        }

        fn get_owner_type(self: @ContractState) -> SignerType {
            self.read_owner().signer_type
        }

        fn get_owner_guid(self: @ContractState) -> felt252 {
            self.read_owner().into_guid()
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
            let signer_signatures: Array<SignerSignature> = self.parse_signature_array(signatures);

            if calls.len() == 1 {
                let call = calls.at(0);
                if *call.to == account_address {
                    let selector = *call.selector;

                    if selector == selector!("trigger_escape_owner") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_guardian_escape_attempt.read());
                            self.last_guardian_escape_attempt.write(get_block_timestamp());
                        }

                        full_deserialize::<Signer>(*call.calldata).expect('argent/invalid-calldata');

                        assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                        let is_valid = self.is_valid_guardian_signature(execution_hash, *signer_signatures.at(0));
                        assert(is_valid, 'argent/invalid-guardian-sig');
                        return; // valid
                    }
                    if selector == selector!("escape_owner") {
                        self.assert_guardian_set();

                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_guardian_escape_attempt.read());
                            self.last_guardian_escape_attempt.write(get_block_timestamp());
                        }

                        assert((*call.calldata).is_empty(), 'argent/invalid-calldata');
                        let current_escape = self._escape.read();
                        assert(current_escape.escape_type == LegacyEscapeType::Owner, 'argent/invalid-escape');

                        assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                        let is_valid = self.is_valid_guardian_signature(execution_hash, *signer_signatures.at(0));
                        assert(is_valid, 'argent/invalid-guardian-sig');
                        return; // valid
                    }
                    if selector == selector!("trigger_escape_guardian") {
                        self.assert_guardian_set();

                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_owner_escape_attempt.read());
                            self.last_owner_escape_attempt.write(get_block_timestamp());
                        }

                        let new_guardian: Option<Signer> = full_deserialize(*call.calldata)
                            .expect('argent/invalid-calldata');

                        if let Option::Some(new_guardian) = new_guardian {
                            assert(new_guardian.signer_type() == SignerType::Starknet, 'argent/invalid-guardian-type');
                        } else {
                            assert(self.read_guardian_backup().is_none(), 'argent/backup-should-be-null');
                        }

                        assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                        let is_valid = self.is_valid_owner_signature(execution_hash, *signer_signatures.at(0));
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

                        assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                        let is_valid = self.is_valid_owner_signature(execution_hash, *signer_signatures.at(0));
                        assert(is_valid, 'argent/invalid-owner-sig');
                        return; // valid
                    }
                    assert(selector != selector!("execute_after_upgrade"), 'argent/forbidden-call');
                    assert(selector != selector!("perform_upgrade"), 'argent/forbidden-call');
                }
            } else {
                // make sure no call is to the account
                assert_no_self_call(calls, account_address);
            }

            self.assert_valid_span_signature(execution_hash, signer_signatures);
        }

        #[inline(always)]
        fn parse_signature_array(self: @ContractState, mut signatures: Span<felt252>) -> Array<SignerSignature> {
            // Check if it's a legacy signature array (there's no support for guardian backup)
            // Legacy signatures are always 2 or 4 items long
            // Shortest signature in modern format is at least 5 items [array_len, signer_type, signer_pubkey, r, s]
            if signatures.len() != 2 && signatures.len() != 4 {
                // manual inlining instead of calling full_deserialize for performance
                let deserialized: Array<SignerSignature> = Serde::deserialize(ref signatures)
                    .expect('argent/invalid-signature-format');
                assert(signatures.is_empty(), 'argent/invalid-signature-length');
                return deserialized;
            }

            let owner_signature = SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: self._signer.read().try_into().expect('argent/zero-pubkey') },
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

        #[must_use]
        fn is_valid_span_signature(
            self: @ContractState, hash: felt252, signer_signatures: Array<SignerSignature>
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

        fn assert_valid_span_signature(self: @ContractState, hash: felt252, signer_signatures: Array<SignerSignature>) {
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
        fn is_valid_owner_signature(self: @ContractState, hash: felt252, signer_signature: SignerSignature) -> bool {
            let signer = signer_signature.signer().storage_value();
            if !self.is_valid_owner(signer) {
                return false;
            }
            return signer_signature.is_valid_signature(hash) || is_estimate_transaction();
        }

        #[must_use]
        fn is_valid_guardian_signature(self: @ContractState, hash: felt252, signer_signature: SignerSignature) -> bool {
            let signer = signer_signature.signer().storage_value();
            if !self.is_valid_guardian(signer) && !self.is_valid_guardian_backup(signer) {
                return false;
            }
            return signer_signature.is_valid_signature(hash) || is_estimate_transaction();
        }

        /// The signature is the result of signing the message hash with the new owner private key
        /// The message hash is the result of hashing the array:
        /// [change_owner selector, chainid, contract address, old_owner]
        /// as specified here: https://docs.starknet.io/documentation/architecture_and_concepts/Hashing/hash-functions/#array_hashing
        fn assert_valid_new_owner_signature(self: @ContractState, signer_signature: SignerSignature) {
            let chain_id = get_tx_info().unbox().chain_id;
            let owner_guid = self.read_owner().into_guid();
            // We now need to hash message_hash with the size of the array: (change_owner selector, chain id, contract address, old_owner_guid)
            // https://github.com/starkware-libs/cairo-lang/blob/b614d1867c64f3fb2cf4a4879348cfcf87c3a5a7/src/starkware/cairo/common/hash_state.py#L6
            let message_hash = PedersenTrait::new(0)
                .update(selector!("change_owner"))
                .update(chain_id)
                .update(get_contract_address().into())
                .update(owner_guid)
                .update(4)
                .finalize();

            let is_valid = signer_signature.is_valid_signature(message_hash);
            assert(is_valid, 'argent/invalid-owner-sig');
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
            self.last_owner_escape_attempt.write(0);
            self.last_guardian_escape_attempt.write(0);
        }

        #[inline(always)]
        fn init_owner(ref self: ContractState, owner: SignerStorageValue) {
            match owner.signer_type {
                SignerType::Starknet => self._signer.write(owner.stored_value),
                _ => self._signer_non_stark.write(owner.signer_type.into(), owner.stored_value),
            }
        }

        fn write_owner(ref self: ContractState, owner: SignerStorageValue) {
            // clear storage
            let old_owner = self.read_owner();
            match old_owner.signer_type {
                SignerType::Starknet => self._signer.write(0),
                _ => self._signer_non_stark.write(old_owner.signer_type.into(), 0),
            }
            // write storage
            match owner.signer_type {
                SignerType::Starknet => self._signer.write(owner.stored_value),
                _ => self._signer_non_stark.write(owner.signer_type.into(), owner.stored_value),
            }
        }

        fn read_owner(self: @ContractState) -> SignerStorageValue {
            let mut preferred_order = owner_ordered_types();
            loop {
                let signer_type = *preferred_order.pop_front().expect('argent/owner-not-found');
                let stored_value = match signer_type {
                    SignerType::Starknet => self._signer.read(),
                    _ => self._signer_non_stark.read(signer_type.into()),
                };
                if stored_value != 0 {
                    break SignerStorageValue { stored_value: stored_value.try_into().unwrap(), signer_type };
                }
            }
        }

        #[inline(always)]
        fn is_valid_owner(self: @ContractState, owner: SignerStorageValue) -> bool {
            match owner.signer_type {
                SignerType::Starknet => self._signer.read() == owner.stored_value,
                _ => self._signer_non_stark.read(owner.signer_type.into()) == owner.stored_value,
            }
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

    fn owner_ordered_types() -> Span<SignerType> {
        array![
            SignerType::Starknet, SignerType::Eip191, SignerType::Webauthn, SignerType::Secp256r1, SignerType::Secp256k1
        ]
            .span()
    }

    fn guardian_ordered_types() -> Span<SignerType> {
        array![
            SignerType::Starknet, SignerType::Eip191, SignerType::Webauthn, SignerType::Secp256r1, SignerType::Secp256k1
        ]
            .span()
    }
}
