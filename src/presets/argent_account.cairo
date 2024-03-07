#[starknet::contract(account)]
mod ArgentAccount {
    use argent::account::interface::{IAccount, IArgentAccount, IArgentUserAccount, IDeprecatedArgentAccount, Version};
    use argent::introspection::src5::src5_component;
    use argent::outside_execution::{
        outside_execution::outside_execution_component, interface::{IOutsideExecutionCallback}
    };
    use argent::recovery::interface::{LegacyEscape, LegacyEscapeType, EscapeStatus};
    use argent::session::{
        interface::SessionToken, session::{session_component::{Internal, InternalTrait}, session_component,}
    };
    use argent::signer::{
        signer_signature::{
            Signer, StarknetSigner, StarknetSignature, SignerTrait, SignerSignature, SignerSignatureTrait,
            starknet_signer_from_pubkey
        }
    };
    use argent::upgrade::{upgrade::upgrade_component, interface::IUpgradableCallback};
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_protocol, assert_only_self}, calls::execute_multicall,
        serialization::full_deserialize,
        transaction_version::{
            TX_V1, TX_V1_ESTIMATE, TX_V3, TX_V3_ESTIMATE, assert_correct_invoke_version, assert_correct_declare_version,
            assert_correct_deploy_account_version, assert_no_unsupported_v3_fields, DA_MODE_L1
        }
    };
    use hash::HashStateTrait;
    use pedersen::PedersenTrait;
    use starknet::{
        ClassHash, get_block_timestamp, get_contract_address, VALIDATED, replace_class_syscall, account::Call,
        SyscallResultTrait, get_tx_info, get_execution_info, syscalls::storage_read_syscall,
        storage_access::{storage_address_from_base_and_offset, storage_base_address_from_felt252, storage_write_syscall}
    };

    const NAME: felt252 = 'ArgentAccount';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 4;
    const VERSION_PATCH: u8 = 0;
    const VERSION_COMPAT: felt252 = '0.4.0';

    /// Time it takes for the escape to become ready after being triggered
    const ESCAPE_SECURITY_PERIOD: u64 = consteval_int!(7 * 24 * 60 * 60); // 7 days
    ///  The escape will be ready and can be completed for this duration
    const ESCAPE_EXPIRY_PERIOD: u64 = consteval_int!(7 * 24 * 60 * 60); // 7 days
    /// Limit amount of escape a party can do to once every X hours
    const TIME_BETWEEN_TWO_ESCAPE: u64 = consteval_int!(12 * 60 * 60); // 12 hours;

    /// Limits fee in escapes
    const MAX_ESCAPE_MAX_FEE_ETH: u128 = 50000000000000000; // 0.05 ETH
    const MAX_ESCAPE_MAX_FEE_STRK: u128 = 50_000000000000000000; // 50 STRK
    const MAX_ESCAPE_TIP_STRK: u128 = 1_000000000000000000; // 1 STRK


    #[abi(embed_v0)]
    impl Sessionable = session_component::SessionImpl<ContractState>;
    // session 
    component!(path: session_component, storage: session, event: SessionableEvents);
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
        _signer: felt252, /// Current account owner
        _guardian: felt252, /// Current account guardian
        _guardian_backup: felt252, /// Current account backup guardian
        _escape: LegacyEscape, /// The ongoing escape, if any
        /// Keeps track of the last time an escape was performed by the guardian.
        /// Rounded down to the hour: https://community.starknet.io/t/starknet-v0-13-1-pre-release-notes/113664 
        /// Used to limit the number of transactions the account will pay for
        /// It resets when an escape is completed or canceled
        guardian_escape_timestamp: u64,
        /// Keeps track of the last time an escape was performed by the owner. 
        /// Rounded down to the hour: https://community.starknet.io/t/starknet-v0-13-1-pre-release-notes/113664 
        /// Used to limit the number of transactions the account will pay for
        /// It resets when an escape is completed or canceled
        owner_escape_timestamp: u64
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
        AccountCreated: AccountCreated,
        TransactionExecuted: TransactionExecuted,
        EscapeOwnerTriggered: EscapeOwnerTriggered,
        EscapeGuardianTriggered: EscapeGuardianTriggered,
        OwnerEscaped: OwnerEscaped,
        GuardianEscaped: GuardianEscaped,
        EscapeCanceled: EscapeCanceled,
        OwnerChanged: OwnerChanged,
        GuardianChanged: GuardianChanged,
        GuardianBackupChanged: GuardianBackupChanged,
        OwnerAdded: OwnerAdded,
        OwnerRemoved: OwnerRemoved,
        SignerLinked: SignerLinked,
    }

    /// @notice Emitted exactly once when the account is initialized
    /// @param account The account address
    /// @param owner The owner address
    /// @param guardian The guardian address
    #[derive(Drop, starknet::Event)]
    struct AccountCreated {
        #[key]
        owner: felt252,
        guardian: felt252
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
    /// @param new_owner new owner address to be set after the security period
    #[derive(Drop, starknet::Event)]
    struct EscapeOwnerTriggered {
        ready_at: u64,
        new_owner: felt252
    }

    /// @notice Guardian escape was triggered by the owner
    /// @param ready_at when the escape can be completed
    /// @param new_guardian address of the new guardian to be set after the security period. O if the guardian will be removed
    #[derive(Drop, starknet::Event)]
    struct EscapeGuardianTriggered {
        ready_at: u64,
        new_guardian: felt252
    }

    /// @notice Owner escape was completed and there is a new account owner
    /// @param new_owner new owner address
    #[derive(Drop, starknet::Event)]
    struct OwnerEscaped {
        new_owner: felt252
    }

    /// @notice Guardian escape was completed and there is a new account guardian
    /// @param new_guardian address of the new guardian or 0 if it was removed
    #[derive(Drop, starknet::Event)]
    struct GuardianEscaped {
        new_guardian: felt252
    }

    /// An ongoing escape was canceled
    #[derive(Drop, starknet::Event)]
    struct EscapeCanceled {}

    /// @notice The account owner was changed
    /// @param new_owner new owner address
    #[derive(Drop, starknet::Event)]
    struct OwnerChanged {
        new_owner: felt252
    }

    /// @notice The account guardian was changed or removed
    /// @param new_guardian address of the new guardian or 0 if it was removed
    #[derive(Drop, starknet::Event)]
    struct GuardianChanged {
        new_guardian: felt252
    }

    /// @notice The account backup guardian was changed or removed
    /// @param new_guardian_backup address of the backup guardian or 0 if it was removed
    #[derive(Drop, starknet::Event)]
    struct GuardianBackupChanged {
        new_guardian_backup: felt252
    }

    /// This event is part of an account discoverability standard, SNIP not yet created
    /// Emitted when an account owner is added, including when the account is created.
    /// Should also be emitted with the current owners when upgrading an account from Cairo 0
    #[derive(Drop, starknet::Event)]
    struct OwnerAdded {
        #[key]
        new_owner_guid: felt252
    }

    /// This event is part of an account discoverability standard, SNIP not yet created
    /// Emitted when an account owner is removed
    #[derive(Drop, starknet::Event)]
    struct OwnerRemoved {
        #[key]
        removed_owner_guid: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct SignerLinked {
        #[key]
        signer_guid: felt252,
        signer: Signer,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: Signer, guardian: Option<Signer>) {
        let owner_guid: felt252 = owner.into_guid();
        self._signer.write(owner_guid);
        self.emit(OwnerAdded { new_owner_guid: owner_guid });
        self.emit(SignerLinked { signer_guid: owner_guid, signer: owner });

        let guardian_guid: felt252 = match guardian {
            Option::Some(guardian) => {
                let guardian_guid: felt252 = guardian.into_guid();
                self._guardian.write(guardian_guid);
                self.emit(SignerLinked { signer_guid: guardian_guid, signer: guardian });
                guardian_guid
            },
            Option::None => { 0 },
        };
        self.emit(AccountCreated { owner: owner_guid, guardian: guardian_guid });
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            assert_only_protocol();
            let tx_info = get_tx_info().unbox();
            assert_correct_invoke_version(tx_info.version);
            assert_no_unsupported_v3_fields();
            if self.session.is_session(*tx_info.signature[0]) {
                self.session.assert_valid_session(calls.span(), tx_info.transaction_hash, tx_info.signature,);
            } else {
                self
                    .assert_valid_calls_and_signature(
                        calls.span(), tx_info.transaction_hash, tx_info.signature, is_from_outside: false
                    );
            }
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert_only_protocol();
            let tx_info = get_tx_info().unbox();
            assert_correct_invoke_version(tx_info.version);
            let signature = tx_info.signature;
            if self.session.is_session(*signature[0]) {
                let session_timestamp = *signature[1];
                // can call unwrap safely as the session has already been deserialized 
                let session_timestamp_u64 = session_timestamp.try_into().unwrap();
                assert(session_timestamp_u64 >= get_block_timestamp(), 'session/expired');
            }

            let retdata = execute_multicall(calls.span());

            self.emit(TransactionExecuted { hash: tx_info.transaction_hash, response: retdata.span() });
            retdata
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            let signer_signatures: Array<SignerSignature> = full_deserialize(signature.span())
                .expect('argent/signature-not-empty');
            if self.is_valid_span_signature(hash, signer_signatures) {
                VALIDATED
            } else {
                0
            }
        }
    }

    // Required Callbacks

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            // As the storage layout for the escape is changing, if there is an ongoing escape it should revert
            // We have to use raw syscall, as using the read fn would make use of the new way of reading
            let base = storage_base_address_from_felt252(selector!("_escape"));
            let ready_at = storage_read_syscall(0, storage_address_from_base_and_offset(base, 0)).unwrap_syscall();
            assert(ready_at.is_zero(), 'argent/ready-at-shoud-be-null');
            let escape_type = storage_read_syscall(0, storage_address_from_base_and_offset(base, 1)).unwrap_syscall();
            assert(escape_type.is_zero(), 'argent/esc-type-shoud-be-null');
            let new_signer = storage_read_syscall(0, storage_address_from_base_and_offset(base, 2)).unwrap_syscall();
            assert(new_signer.is_zero(), 'argent/new-signer-shoud-be-null');

            // Cleaning attempts storage => This should NOT have any impact as we don't allow to upgrade if there is an escape ongoing
            let base = storage_base_address_from_felt252(selector!("guardian_escape_attempts"));
            storage_write_syscall(0, storage_address_from_base_and_offset(base, 0), 0).unwrap_syscall();
            let base = storage_base_address_from_felt252(selector!("owner_escape_attempts"));
            storage_write_syscall(0, storage_address_from_base_and_offset(base, 0), 0).unwrap_syscall();

            // Check basic invariants and emit missing events
            let owner = self._signer.read();
            let guardian = self._guardian.read();
            let guardian_backup = self._guardian_backup.read();
            assert(owner != 0, 'argent/null-owner');
            if guardian == 0 {
                assert(guardian_backup == 0, 'argent/backup-should-be-null');
            } else {
                self.emit(SignerLinked { signer_guid: guardian, signer: starknet_signer_from_pubkey(guardian) });
                if (guardian_backup != 0) {
                    self
                        .emit(
                            SignerLinked {
                                signer_guid: guardian_backup, signer: starknet_signer_from_pubkey(guardian_backup)
                            }
                        );
                }
            }
            self.emit(SignerLinked { signer_guid: owner, signer: starknet_signer_from_pubkey(owner) });

            let implementation = self._implementation.read();
            if implementation != Zeroable::zero() {
                replace_class_syscall(implementation).expect('argent/invalid-after-upgrade');
                self._implementation.write(Zeroable::zero());
                // Technically the owner is not added here, but we emit the event since it wasn't emitted in previous versions
                self.emit(OwnerAdded { new_owner_guid: owner });
            }

            if data.is_empty() {
                return array![];
            }

            let mut data_span = data.span();
            let calls: Array<Call> = Serde::deserialize(ref data_span).expect('argent/invalid-calls');
            assert(data_span.is_empty(), 'argent/invalid-calls');

            assert_no_self_call(calls.span(), get_contract_address());

            let multicall_return = execute_multicall(calls.span());
            let mut output = array![];
            multicall_return.serialize(ref output);
            output
        }
    }

    impl OutsideExecutionCallbackImpl of IOutsideExecutionCallback<ContractState> {
        #[inline(always)]
        fn execute_from_outside_callback(
            ref self: ContractState, calls: Span<Call>, outside_execution_hash: felt252, signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            if self.session.is_session(*signature[0]) {
                self.session.assert_valid_session(calls, outside_execution_hash, signature);
            } else {
                self.assert_valid_calls_and_signature(calls, outside_execution_hash, signature, is_from_outside: true);
            }
            let retdata = execute_multicall(calls);
            self.emit(TransactionExecuted { hash: outside_execution_hash, response: retdata.span() });
            retdata
        }
    }

    #[abi(embed_v0)]
    impl ArgentUserAccountImpl of IArgentUserAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let tx_info = get_tx_info().unbox();
            assert_correct_declare_version(tx_info.version);
            assert_no_unsupported_v3_fields();
            let mut signatures = tx_info.signature;
            let signer_signatures: Array<SignerSignature> = full_deserialize(signatures)
                .expect('argent/signature-not-empty');
            self.assert_valid_span_signature(tx_info.transaction_hash, signer_signatures);
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
            assert_no_unsupported_v3_fields();
            let mut signatures = tx_info.signature;
            let signer_signatures: Array<SignerSignature> = full_deserialize(signatures)
                .expect('argent/signature-not-empty');
            self.assert_valid_span_signature(tx_info.transaction_hash, signer_signatures);
            VALIDATED
        }

        fn change_owner(ref self: ContractState, signer_signature: SignerSignature) {
            assert_only_self();

            self.reset_escape();
            self.reset_escape_timestamps();

            let new_owner_guid = signer_signature.signer().into_guid();
            let old_owner = self._signer.read();
            self.assert_valid_new_owner_signature(signer_signature);

            self._signer.write(new_owner_guid);
            self.emit(OwnerChanged { new_owner: new_owner_guid });
            self.emit(OwnerRemoved { removed_owner_guid: old_owner });
            self.emit(OwnerAdded { new_owner_guid: new_owner_guid });
            self.emit(SignerLinked { signer_guid: new_owner_guid, signer: signer_signature.signer() });
        }

        fn change_guardian(ref self: ContractState, new_guardian: Option<Signer>) {
            assert_only_self();

            let new_guardian_guid: felt252 = match new_guardian {
                Option::Some(guardian) => {
                    let guardian_guid = guardian.into_guid();
                    self.emit(SignerLinked { signer_guid: guardian_guid, signer: guardian });
                    guardian_guid
                },
                Option::None => { 0 },
            };

            // There cannot be a guardian_backup when there is no guardian
            if (new_guardian_guid == 0) {
                assert(self._guardian_backup.read() == 0, 'argent/backup-should-be-null');
            }

            self.reset_escape();
            self.reset_escape_timestamps();

            self._guardian.write(new_guardian_guid);
            self.emit(GuardianChanged { new_guardian: new_guardian_guid });
        }

        fn change_guardian_backup(ref self: ContractState, new_guardian_backup: Option<Signer>) {
            assert_only_self();
            self.assert_guardian_set();

            let new_guardian_backup_guid: felt252 = match new_guardian_backup {
                Option::Some(guardian) => {
                    let guardian_guid = guardian.into_guid();
                    self.emit(SignerLinked { signer_guid: guardian_guid, signer: guardian });
                    guardian_guid
                },
                Option::None => { 0_felt252 },
            };

            self.reset_escape();
            self.reset_escape_timestamps();

            self._guardian_backup.write(new_guardian_backup_guid);
            self.emit(GuardianBackupChanged { new_guardian_backup: new_guardian_backup_guid });
        }

        fn trigger_escape_owner(ref self: ContractState, new_owner: Signer) {
            assert_only_self();

            // no escape if there is a guardian escape triggered by the owner in progress
            let current_escape = self._escape.read();
            if current_escape.escape_type == LegacyEscapeType::Guardian {
                assert(
                    get_escape_status(current_escape.ready_at) == EscapeStatus::Expired, 'argent/cannot-override-escape'
                );
            }

            self.reset_escape();
            let new_owner_guid = new_owner.into_guid();
            let ready_at = get_block_timestamp() + ESCAPE_SECURITY_PERIOD;
            let escape = LegacyEscape { ready_at, escape_type: LegacyEscapeType::Owner, new_signer: new_owner_guid };
            self._escape.write(escape);
            self.emit(EscapeOwnerTriggered { ready_at, new_owner: new_owner_guid });
            self.emit(SignerLinked { signer_guid: new_owner_guid, signer: new_owner });
        }

        fn trigger_escape_guardian(ref self: ContractState, new_guardian: Option<Signer>) {
            assert_only_self();

            self.reset_escape();

            let new_guardian_guid: felt252 = match new_guardian {
                Option::Some(guardian) => {
                    let guardian_guid = guardian.into_guid();
                    self.emit(SignerLinked { signer_guid: guardian_guid, signer: guardian });
                    guardian_guid
                },
                Option::None => { 0 },
            };

            let ready_at = get_block_timestamp() + ESCAPE_SECURITY_PERIOD;
            let escape = LegacyEscape {
                ready_at, escape_type: LegacyEscapeType::Guardian, new_signer: new_guardian_guid
            };
            self._escape.write(escape);
            self.emit(EscapeGuardianTriggered { ready_at, new_guardian: new_guardian_guid });
        }

        fn escape_owner(ref self: ContractState) {
            assert_only_self();

            let current_escape = self._escape.read();

            let current_escape_status = get_escape_status(current_escape.ready_at);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            self.reset_escape_timestamps();

            // update owner
            let old_owner = self._signer.read();
            self._signer.write(current_escape.new_signer);
            self.emit(OwnerEscaped { new_owner: current_escape.new_signer });
            self.emit(OwnerRemoved { removed_owner_guid: old_owner });
            self.emit(OwnerAdded { new_owner_guid: current_escape.new_signer });

            // clear escape
            self._escape.write(Default::default());
        }

        fn escape_guardian(ref self: ContractState) {
            assert_only_self();

            let current_escape = self._escape.read();
            // TODO This could be done during validation?
            assert(get_escape_status(current_escape.ready_at) == EscapeStatus::Ready, 'argent/invalid-escape');

            self.reset_escape_timestamps();

            //update guardian
            self._guardian.write(current_escape.new_signer);
            self.emit(GuardianEscaped { new_guardian: current_escape.new_signer });
            // clear escape
            self._escape.write(Default::default());
        }

        fn cancel_escape(ref self: ContractState) {
            assert_only_self();
            let current_escape = self._escape.read();
            let current_escape_status = get_escape_status(current_escape.ready_at);
            assert(current_escape_status != EscapeStatus::None, 'argent/invalid-escape');
            self.reset_escape();
            self.reset_escape_timestamps();
        }

        fn get_owner(self: @ContractState) -> felt252 {
            self._signer.read()
        }

        fn get_guardian(self: @ContractState) -> felt252 {
            self._guardian.read()
        }

        fn get_guardian_backup(self: @ContractState) -> felt252 {
            self._guardian_backup.read()
        }

        fn get_escape(self: @ContractState) -> LegacyEscape {
            self._escape.read()
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        fn get_guardian_escape_last_attempt_timestamp(self: @ContractState) -> u64 {
            self.guardian_escape_timestamp.read()
        }

        fn get_owner_escape_last_attempt_timestamp(self: @ContractState) -> u64 {
            self.owner_escape_timestamp.read()
        }

        /// Current escape if any, and its status
        fn get_escape_and_status(self: @ContractState) -> (LegacyEscape, EscapeStatus) {
            let current_escape = self._escape.read();
            (current_escape, get_escape_status(current_escape.ready_at))
        }
    }

    // TODO is this still needed?
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
            is_from_outside: bool
        ) {
            let execution_info = get_execution_info().unbox();
            let account_address = execution_info.contract_address;

            let signer_signatures: Array<SignerSignature> = self.parse_signature_array(signatures);

            if calls.len() == 1 {
                let call = calls.at(0);
                if *call.to == account_address {
                    let selector = *call.selector;

                    if selector == selector!("trigger_escape_owner") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.guardian_escape_timestamp.read());
                            self.guardian_escape_timestamp.write(get_block_timestamp());
                        }

                        full_deserialize::<Signer>(*call.calldata).expect('argent/invalid-calldata');

                        assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                        let is_valid = self.is_valid_guardian_signature(execution_hash, *signer_signatures.at(0));
                        assert(is_valid, 'argent/invalid-guardian-sig');
                        return; // valid
                    }
                    if selector == selector!("escape_owner") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.guardian_escape_timestamp.read());
                            self.guardian_escape_timestamp.write(get_block_timestamp());
                        }

                        assert((*call.calldata).is_empty(), 'argent/invalid-calldata');
                        self.assert_guardian_set();
                        let current_escape = self._escape.read();
                        assert(current_escape.escape_type == LegacyEscapeType::Owner, 'argent/invalid-escape');
                        // needed if user started escape in old cairo version and
                        // upgraded half way through,  then tries to finish the escape in new version
                        assert(current_escape.new_signer != 0, 'argent/null-owner');

                        assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                        let is_valid = self.is_valid_guardian_signature(execution_hash, *signer_signatures.at(0));
                        assert(is_valid, 'argent/invalid-guardian-sig');
                        return; // valid
                    }
                    if selector == selector!("trigger_escape_guardian") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.owner_escape_timestamp.read());
                            self.owner_escape_timestamp.write(get_block_timestamp());
                        }

                        let new_guardian: Option<Signer> = full_deserialize(*call.calldata)
                            .expect('argent/invalid-calldata');
                        if new_guardian.is_none() {
                            assert(self._guardian_backup.read() == 0, 'argent/backup-should-be-null');
                        }

                        self.assert_guardian_set();

                        assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                        let is_valid = self.is_valid_owner_signature(execution_hash, *signer_signatures.at(0));
                        assert(is_valid, 'argent/invalid-owner-sig');
                        return; // valid
                    }
                    if selector == selector!("escape_guardian") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.owner_escape_timestamp.read());
                            self.owner_escape_timestamp.write(get_block_timestamp());
                        }
                        assert((*call.calldata).is_empty(), 'argent/invalid-calldata');
                        self.assert_guardian_set();
                        let current_escape = self._escape.read();

                        assert(current_escape.escape_type == LegacyEscapeType::Guardian, 'argent/invalid-escape');

                        // needed if user started escape in old cairo version and
                        // upgraded half way through, then tries to finish the escape in new version
                        if current_escape.new_signer == 0 {
                            assert(self._guardian_backup.read() == 0, 'argent/backup-should-be-null');
                        }

                        assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                        let is_valid = self.is_valid_owner_signature(execution_hash, *signer_signatures.at(0));
                        assert(is_valid, 'argent/invalid-owner-sig');
                        return; // valid
                    }
                    assert(selector != selector!("execute_after_upgrade"), 'argent/forbidden-call');
                }
            } else {
                // make sure no call is to the account
                assert_no_self_call(calls, account_address);
            }

            self.assert_valid_span_signature(execution_hash, signer_signatures);
        }

        fn parse_signature_array(self: @ContractState, mut signatures: Span<felt252>) -> Array<SignerSignature> {
            let first_slot: u256 = (*signatures.at(0)).into();
            // check if legacy signature array
            // Note that it will not work if the guardian_backup was used
            if (first_slot > 3 && (signatures.len() == 2 || signatures.len() == 4)) {
                let mut signer_signatures = array![];
                let owner = self._signer.read();
                let sig_owner_r = signatures.pop_front().unwrap();
                let sig_owner_s = signatures.pop_front().unwrap();
                signer_signatures
                    .append(
                        SignerSignature::Starknet(
                            (
                                StarknetSigner { pubkey: owner.try_into().expect('argent/zero-pubkey') },
                                StarknetSignature { r: *sig_owner_r, s: *sig_owner_s }
                            )
                        )
                    );
                match signatures.pop_front() {
                    Option::Some(sig_guardian_r) => {
                        let guardian = self._guardian.read();
                        let sig_guardian_s = signatures.pop_front().unwrap();
                        signer_signatures
                            .append(
                                SignerSignature::Starknet(
                                    (
                                        StarknetSigner { pubkey: guardian.try_into().expect('argent/zero-pubkey') },
                                        StarknetSignature { r: *sig_guardian_r, s: *sig_guardian_s }
                                    )
                                )
                            );
                    },
                    Option::None => {}
                };
                signer_signatures
            } else {
                full_deserialize(signatures).expect('argent/signature-not-empty')
            }
        }

        fn is_valid_span_signature(
            self: @ContractState, hash: felt252, signer_signatures: Array<SignerSignature>
        ) -> bool {
            if self._guardian.read() == 0 {
                assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                self.is_valid_owner_signature(hash, *signer_signatures.at(0))
            } else {
                assert(signer_signatures.len() == 2, 'argent/invalid-signature-length');
                self.is_valid_owner_signature(hash, *signer_signatures.at(0))
                    && self.is_valid_guardian_signature(hash, *signer_signatures.at(1))
            }
        }

        fn assert_valid_span_signature(self: @ContractState, hash: felt252, signer_signatures: Array<SignerSignature>) {
            if self._guardian.read() == 0 {
                assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                assert(self.is_valid_owner_signature(hash, *signer_signatures.at(0)), 'argent/invalid-owner-sig');
            } else {
                assert(signer_signatures.len() == 2, 'argent/invalid-signature-length');
                assert(self.is_valid_owner_signature(hash, *signer_signatures.at(0)), 'argent/invalid-owner-sig');
                assert(self.is_valid_guardian_signature(hash, *signer_signatures.at(1)), 'argent/invalid-guardian-sig');
            }
        }

        fn is_valid_owner_signature(self: @ContractState, hash: felt252, signer_signature: SignerSignature) -> bool {
            signer_signature.signer().into_guid() == self._signer.read() && signer_signature.is_valid_signature(hash)
        }

        fn is_valid_guardian_signature(self: @ContractState, hash: felt252, signer_signature: SignerSignature) -> bool {
            let signer_guid = signer_signature.signer().into_guid();
            (signer_guid == self._guardian.read() || signer_guid == self._guardian_backup.read())
                && signer_signature.is_valid_signature(hash)
        }

        /// The signature is the result of signing the message hash with the new owner private key
        /// The message hash is the result of hashing the array:
        /// [change_owner selector, chainid, contract address, old_owner]
        /// as specified here: https://docs.starknet.io/documentation/architecture_and_concepts/Hashing/hash-functions/#array_hashing
        fn assert_valid_new_owner_signature(self: @ContractState, signer_signature: SignerSignature) {
            let chain_id = get_tx_info().unbox().chain_id;
            // We now need to hash message_hash with the size of the array: (change_owner selector, chainid, contract address, old_owner)
            // https://github.com/starkware-libs/cairo-lang/blob/b614d1867c64f3fb2cf4a4879348cfcf87c3a5a7/src/starkware/cairo/common/hash_state.py#L6
            let message_hash = PedersenTrait::new(0)
                .update(selector!("change_owner"))
                .update(chain_id)
                .update(get_contract_address().into())
                .update(self._signer.read())
                .update(4)
                .finalize();

            let is_valid = signer_signature.is_valid_signature(message_hash);
            assert(is_valid, 'argent/invalid-owner-sig');
        }

        #[inline(always)]
        fn reset_escape(ref self: ContractState) {
            let current_escape_status = get_escape_status(self._escape.read().ready_at);
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
            assert(self._guardian.read() != 0, 'argent/guardian-required');
        }

        #[inline(always)]
        fn reset_escape_timestamps(ref self: ContractState) {
            self.owner_escape_timestamp.write(0);
            self.guardian_escape_timestamp.write(0);
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
                    Option::Some(r) => {
                        let max_resource_amount: u128 = (*r.max_amount).into();
                        max_fee += *r.max_price_per_unit * max_resource_amount;
                        if *r.resource == 'L2_GAS' {
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

        assert(
            last_timestamp.is_zero() || last_timestamp + TIME_BETWEEN_TWO_ESCAPE < get_block_timestamp(),
            'argent/escape-window'
        );
    }

    fn get_escape_status(escape_ready_at: u64) -> EscapeStatus {
        if escape_ready_at == 0 {
            return EscapeStatus::None;
        }

        let block_timestamp = get_block_timestamp();
        if block_timestamp < escape_ready_at {
            return EscapeStatus::NotReady;
        }
        if escape_ready_at + ESCAPE_EXPIRY_PERIOD <= block_timestamp {
            return EscapeStatus::Expired;
        }

        EscapeStatus::Ready
    }
}
