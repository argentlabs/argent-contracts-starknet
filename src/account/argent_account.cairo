#[starknet::contract]
mod ArgentAccount {
    use array::{ArrayTrait, SpanTrait};
    use box::BoxTrait;
    use ecdsa::check_ecdsa_signature;
    use hash::{TupleSize4LegacyHash, LegacyHashFelt252};
    use option::{OptionTrait, OptionTraitImpl};
    use serde::Serde;
    use traits::Into;
    use starknet::{
        ClassHash, class_hash_const, ContractAddress, get_block_timestamp, get_caller_address,
        get_execution_info, get_contract_address, get_tx_info, VALIDATED, replace_class_syscall,
        account::Call
    };

    use argent::account::escape::{Escape, EscapeStatus};
    use argent::account::interface::{IArgentAccount, IDeprecatedArgentAccount};
    use argent::common::{
        account::{
            IAccount, ERC165_ACCOUNT_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID_OLD_1,
            ERC165_ACCOUNT_INTERFACE_ID_OLD_2
        },
        asserts::{
            assert_correct_tx_version, assert_no_self_call, assert_caller_is_null, assert_only_self,
            assert_correct_declare_version
        },
        calls::execute_multicall, version::Version,
        erc165::{
            IErc165, IErc165LibraryDispatcher, IErc165DispatcherTrait, ERC165_IERC165_INTERFACE_ID,
            ERC165_IERC165_INTERFACE_ID_OLD,
        },
        outside_execution::{
            OutsideExecution, IOutsideExecution, hash_outside_execution_message,
            ERC165_OUTSIDE_EXECUTION_INTERFACE_ID
        },
        upgrade::{IUpgradeable, IUpgradeableLibraryDispatcher, IUpgradeableDispatcherTrait}
    };

    const NAME: felt252 = 'ArgentAccount';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 3;
    const VERSION_PATCH: u8 = 0;
    const VERSION_COMPAT: felt252 = '0.3.0';

    /// Time it takes for the escape to become ready after being triggered
    const ESCAPE_SECURITY_PERIOD: u64 = 604800; // 7 * 24 * 60 * 60;  // 7 days
    ///  The escape will be ready and can be completed for this duration
    const ESCAPE_EXPIRY_PERIOD: u64 = 604800; // 7 * 24 * 60 * 60;  // 7 days
    const ESCAPE_TYPE_GUARDIAN: felt252 = 1;
    const ESCAPE_TYPE_OWNER: felt252 = 2;

    const TRIGGER_ESCAPE_GUARDIAN_SELECTOR: felt252 =
        73865429733192804476769961144708816295126306469589518371407068321865763651; // starknet_keccak('trigger_escape_guardian')
    const TRIGGER_ESCAPE_OWNER_SELECTOR: felt252 =
        1099763735485822105046709698985960101896351570185083824040512300972207240555; // starknet_keccak('trigger_escape_owner')
    const ESCAPE_GUARDIAN_SELECTOR: felt252 =
        1662889347576632967292303062205906116436469425870979472602094601074614456040; // starknet_keccak('escape_guardian')
    const ESCAPE_OWNER_SELECTOR: felt252 =
        1621457541430776841129472853859989177600163870003012244140335395142204209277; // starknet_keccak'(escape_owner')
    const EXECUTE_AFTER_UPGRADE_SELECTOR: felt252 =
        738349667340360233096752603318170676063569407717437256101137432051386874767; // starknet_keccak('execute_after_upgrade')
    const CHANGE_OWNER_SELECTOR: felt252 =
        658036363289841962501247229249022783727527757834043681434485756469236076608; // starknet_keccak('change_owner')

    /// Limit escape attempts by only one party
    const MAX_ESCAPE_ATTEMPTS: u32 = 5;
    /// Limits fee in escapes
    const MAX_ESCAPE_MAX_FEE: u128 = 50000000000000000; // 0.05 ETH

    #[storage]
    struct Storage {
        _implementation: ClassHash, // This is deprecated and used to migrate cairo 0 accounts only
        _signer: felt252, /// Current account owner
        _guardian: felt252, /// Current account guardian
        _guardian_backup: felt252, /// Current account backup guardian
        _escape: Escape, /// The ongoing escape, if any
        /// Keeps track of used nonces for outside transactions (`execute_from_outside`)
        outside_nonces: LegacyMap<felt252, bool>,
        /// Keeps track of how many escaping tx the guardian has submitted. Used to limit the number of transactions the account will pay for
        /// It resets when an escape is completed or canceled
        guardian_escape_attempts: u32,
        /// Keeps track of how many escaping tx the owner has submitted. Used to limit the number of transactions the account will pay for
        /// It resets when an escape is completed or canceled
        owner_escape_attempts: u32
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
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
        AccountUpgraded: AccountUpgraded,
        OwnerAdded: OwnerAdded,
        OwnerRemoved: OwnerRemoved,
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

    /// @notice Emitted when the implementation of the account changes
    /// @param new_implementation The new implementation
    #[derive(Drop, starknet::Event)]
    struct AccountUpgraded {
        new_implementation: ClassHash
    }

    /// This event is part of an account discoverability standard, SNIP not yet created
    /// Emitted when an account owner is added, including when the account is created.
    /// Should also be emitted with the current owners when upgrading an account from Cairo 0
    #[derive(Drop, starknet::Event)]
    struct OwnerAdded {
        #[key]
        new_owner_guid: felt252,
    }

    /// This event is part of an account discoverability standard, SNIP not yet created
    /// Emitted when an account owner is removed
    #[derive(Drop, starknet::Event)]
    struct OwnerRemoved {
        #[key]
        removed_owner_guid: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: felt252, guardian: felt252) {
        assert(owner != 0, 'argent/null-owner');

        self._signer.write(owner);
        self._guardian.write(guardian);
        self._guardian_backup.write(0);
        self.emit(AccountCreated { owner, guardian });
        self.emit(OwnerAdded { new_owner_guid: owner });
    }

    #[external(v0)]
    impl Account of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            assert_caller_is_null();
            let tx_info = get_tx_info().unbox();
            self
                .assert_valid_calls_and_signature(
                    calls.span(),
                    tx_info.transaction_hash,
                    tx_info.signature,
                    is_from_outside: false
                );
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert_caller_is_null();
            let tx_info = get_tx_info().unbox();
            assert_correct_tx_version(tx_info.version);

            let retdata = execute_multicall(calls.span());

            let hash = tx_info.transaction_hash;
            let response = retdata.span();
            self.emit(TransactionExecuted { hash, response });
            retdata
        }

        fn is_valid_signature(
            self: @ContractState, hash: felt252, signature: Array<felt252>
        ) -> felt252 {
            if self.is_valid_span_signature(hash, signature.span()) {
                VALIDATED
            } else {
                0
            }
        }
    }

    #[external(v0)]
    impl ExecuteFromOutsideImpl of IOutsideExecution<ContractState> {
        fn execute_from_outside(
            ref self: ContractState, outside_execution: OutsideExecution, signature: Array<felt252>
        ) -> Array<Span<felt252>> {
            // Checks
            if outside_execution.caller.into() != 'ANY_CALLER' {
                assert(get_caller_address() == outside_execution.caller, 'argent/invalid-caller');
            }

            let block_timestamp = get_block_timestamp();
            assert(
                outside_execution.execute_after < block_timestamp
                    && block_timestamp < outside_execution.execute_before,
                'argent/invalid-timestamp'
            );
            let nonce = outside_execution.nonce;
            assert(!self.outside_nonces.read(nonce), 'argent/duplicated-outside-nonce');

            let outside_tx_hash = hash_outside_execution_message(@outside_execution);

            let calls = outside_execution.calls;

            self
                .assert_valid_calls_and_signature(
                    calls, outside_tx_hash, signature.span(), is_from_outside: true
                );

            // Effects
            self.outside_nonces.write(nonce, true);

            // Interactions
            let retdata = execute_multicall(calls);

            self.emit(TransactionExecuted { hash: outside_tx_hash, response: retdata.span() });
            retdata
        }

        fn get_outside_execution_message_hash(
            self: @ContractState, outside_execution: OutsideExecution
        ) -> felt252 {
            hash_outside_execution_message(@outside_execution)
        }

        fn is_valid_outside_execution_nonce(self: @ContractState, nonce: felt252) -> bool {
            !self.outside_nonces.read(nonce)
        }
    }

    #[external(v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        /// Must be called by the account and authorised by the owner and a guardian (if guardian is set).
        fn upgrade(
            ref self: ContractState, new_implementation: ClassHash, calldata: Array<felt252>
        ) -> Array<felt252> {
            assert_only_self();

            let supports_interface = IErc165LibraryDispatcher {
                class_hash: new_implementation
            }.supports_interface(ERC165_ACCOUNT_INTERFACE_ID);
            assert(supports_interface, 'argent/invalid-implementation');

            replace_class_syscall(new_implementation).unwrap_syscall();
            self.emit(AccountUpgraded { new_implementation });

            IUpgradeableLibraryDispatcher {
                class_hash: new_implementation
            }.execute_after_upgrade(calldata)
        }

        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            // Check basic invariants
            assert(self._signer.read() != 0, 'argent/null-owner');
            if self._guardian.read() == 0 {
                assert(self._guardian_backup.read() == 0, 'argent/backup-should-be-null');
            }

            let implementation = self._implementation.read();
            if implementation != class_hash_const::<0>() {
                replace_class_syscall(implementation).unwrap_syscall();
                self._implementation.write(class_hash_const::<0>());
                // Technically the owner is not added here, but we emit the event since it wasn't emitted in previous versions
                self.emit(OwnerAdded { new_owner_guid: self._signer.read() });
            }

            if data.is_empty() {
                return ArrayTrait::new();
            }

            let mut data_span = data.span();
            let calls: Array<Call> = Serde::deserialize(ref data_span)
                .expect('argent/invalid-calls');
            assert(data_span.is_empty(), 'argent/invalid-calls');

            assert_no_self_call(calls.span(), get_contract_address());

            let multicall_return = execute_multicall(calls.span());
            let mut output = ArrayTrait::new();
            multicall_return.serialize(ref output);
            output
        }
    }

    #[external(v0)]
    impl ArgentAccountImpl of IArgentAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let tx_info = get_tx_info().unbox();
            assert_correct_declare_version(tx_info.version);
            self.assert_valid_span_signature(tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: felt252,
            guardian: felt252
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            assert_correct_tx_version(tx_info.version);
            self.assert_valid_span_signature(tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn change_owner(
            ref self: ContractState, new_owner: felt252, signature_r: felt252, signature_s: felt252
        ) {
            assert_only_self();
            self.assert_valid_new_owner(new_owner, signature_r, signature_s);

            self.reset_escape();
            self.reset_escape_attempts();

            let old_owner = self._signer.read();

            self._signer.write(new_owner);
            self.emit(OwnerChanged { new_owner });
            self.emit(OwnerRemoved { removed_owner_guid: old_owner });
            self.emit(OwnerAdded { new_owner_guid: new_owner });
        }

        fn change_guardian(ref self: ContractState, new_guardian: felt252) {
            assert_only_self();
            // There cannot be a guardian_backup when there is no guardian
            if new_guardian == 0 {
                assert(self._guardian_backup.read() == 0, 'argent/backup-should-be-null');
            }

            self.reset_escape();
            self.reset_escape_attempts();

            self._guardian.write(new_guardian);
            self.emit(GuardianChanged { new_guardian });
        }

        fn change_guardian_backup(ref self: ContractState, new_guardian_backup: felt252) {
            assert_only_self();
            self.assert_guardian_set();

            self.reset_escape();
            self.reset_escape_attempts();

            self._guardian_backup.write(new_guardian_backup);
            self.emit(GuardianBackupChanged { new_guardian_backup });
        }

        fn trigger_escape_owner(ref self: ContractState, new_owner: felt252) {
            assert_only_self();

            // no escape if there is a guardian escape triggered by the owner in progress
            let current_escape = self._escape.read();
            if current_escape.escape_type == ESCAPE_TYPE_GUARDIAN {
                assert(
                    get_escape_status(current_escape.ready_at) == EscapeStatus::Expired(()),
                    'argent/cannot-override-escape'
                );
            }

            self.reset_escape();
            let ready_at = get_block_timestamp() + ESCAPE_SECURITY_PERIOD;
            let escape = Escape { ready_at, escape_type: ESCAPE_TYPE_OWNER, new_signer: new_owner };
            self._escape.write(escape);
            self.emit(EscapeOwnerTriggered { ready_at, new_owner });
        }

        fn trigger_escape_guardian(ref self: ContractState, new_guardian: felt252) {
            assert_only_self();

            self.reset_escape();

            let ready_at = get_block_timestamp() + ESCAPE_SECURITY_PERIOD;
            let escape = Escape {
                ready_at, escape_type: ESCAPE_TYPE_GUARDIAN, new_signer: new_guardian
            };
            self._escape.write(escape);
            self.emit(EscapeGuardianTriggered { ready_at, new_guardian });
        }

        fn escape_owner(ref self: ContractState) {
            assert_only_self();

            let current_escape = self._escape.read();

            let current_escape_status = get_escape_status(current_escape.ready_at);
            assert(current_escape_status == EscapeStatus::Ready(()), 'argent/invalid-escape');

            self.reset_escape_attempts();

            // update owner
            let old_owner = self._signer.read();
            self._signer.write(current_escape.new_signer);
            self.emit(OwnerEscaped { new_owner: current_escape.new_signer });
            self.emit(OwnerRemoved { removed_owner_guid: old_owner });
            self.emit(OwnerAdded { new_owner_guid: current_escape.new_signer });

            // clear escape
            self._escape.write(Escape { ready_at: 0, escape_type: 0, new_signer: 0 });
        }

        fn escape_guardian(ref self: ContractState) {
            assert_only_self();

            let current_escape = self._escape.read();
            assert(
                get_escape_status(current_escape.ready_at) == EscapeStatus::Ready(()),
                'argent/invalid-escape'
            );

            self.reset_escape_attempts();

            //update guardian
            self._guardian.write(current_escape.new_signer);
            self.emit(GuardianEscaped { new_guardian: current_escape.new_signer });
            // clear escape
            self._escape.write(Escape { ready_at: 0, escape_type: 0, new_signer: 0 });
        }

        fn cancel_escape(ref self: ContractState) {
            assert_only_self();
            let current_escape = self._escape.read();
            let current_escape_status = get_escape_status(current_escape.ready_at);
            assert(current_escape_status != EscapeStatus::None(()), 'argent/invalid-escape');
            self.reset_escape();
            self.reset_escape_attempts();
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

        fn get_escape(self: @ContractState) -> Escape {
            self._escape.read()
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        fn get_guardian_escape_attempts(self: @ContractState) -> u32 {
            self.guardian_escape_attempts.read()
        }

        fn get_owner_escape_attempts(self: @ContractState) -> u32 {
            self.owner_escape_attempts.read()
        }

        /// Current escape if any, and its status
        fn get_escape_and_status(self: @ContractState) -> (Escape, EscapeStatus) {
            let current_escape = self._escape.read();
            (current_escape, get_escape_status(current_escape.ready_at))
        }
    }

    #[external(v0)]
    impl Erc165Impl of IErc165<ContractState> {
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            if interface_id == ERC165_IERC165_INTERFACE_ID {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID {
                true
            } else if interface_id == ERC165_OUTSIDE_EXECUTION_INTERFACE_ID {
                true
            } else if interface_id == ERC165_IERC165_INTERFACE_ID_OLD {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID_OLD_1 {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID_OLD_2 {
                true
            } else {
                false
            }
        }
    }

    #[external(v0)]
    impl OldArgentAccountImpl<
        impl ArgentAccount: IArgentAccount<ContractState>,
        impl Account: IAccount<ContractState>,
        impl Erc165: IErc165<ContractState>,
    > of IDeprecatedArgentAccount<ContractState> {
        fn getVersion(self: @ContractState) -> felt252 {
            VERSION_COMPAT
        }

        fn getName(self: @ContractState) -> felt252 {
            ArgentAccount::get_name(self)
        }

        fn supportsInterface(self: @ContractState, interface_id: felt252) -> felt252 {
            if Erc165::supports_interface(self, interface_id) {
                1
            } else {
                0
            }
        }

        fn isValidSignature(
            self: @ContractState, hash: felt252, signatures: Array<felt252>
        ) -> felt252 {
            assert(
                Account::is_valid_signature(self, hash, signatures) == VALIDATED,
                'argent/invalid-signature'
            );
            1
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls_and_signature(
            ref self: ContractState,
            calls: Span<Call>,
            execution_hash: felt252,
            signature: Span<felt252>,
            is_from_outside: bool
        ) {
            let execution_info = get_execution_info().unbox();
            let account_address = execution_info.contract_address;
            let tx_info = execution_info.tx_info.unbox();
            assert_correct_tx_version(tx_info.version);

            if calls.len() == 1 {
                let call = calls.at(0);
                if *call.to == account_address {
                    let selector = *call.selector;

                    if selector == TRIGGER_ESCAPE_OWNER_SELECTOR {
                        if !is_from_outside {
                            let current_attempts = self.guardian_escape_attempts.read();
                            assert_valid_escape_parameters(current_attempts);
                            self.guardian_escape_attempts.write(current_attempts + 1);
                        }

                        let mut calldata: Span<felt252> = call.calldata.span();
                        let new_owner: felt252 = Serde::deserialize(ref calldata)
                            .expect('argent/invalid-calldata');
                        assert(calldata.is_empty(), 'argent/invalid-calldata');
                        assert(new_owner != 0, 'argent/null-owner');
                        self.assert_guardian_set();

                        let is_valid = self.is_valid_guardian_signature(execution_hash, signature);
                        assert(is_valid, 'argent/invalid-guardian-sig');
                        return; // valid
                    }
                    if selector == ESCAPE_OWNER_SELECTOR {
                        if !is_from_outside {
                            let current_attempts = self.guardian_escape_attempts.read();
                            assert_valid_escape_parameters(current_attempts);
                            self.guardian_escape_attempts.write(current_attempts + 1);
                        }

                        assert(call.calldata.is_empty(), 'argent/invalid-calldata');
                        self.assert_guardian_set();
                        let current_escape = self._escape.read();
                        assert(
                            current_escape.escape_type == ESCAPE_TYPE_OWNER, 'argent/invalid-escape'
                        );
                        // needed if user started escape in old cairo version and
                        // upgraded half way through,  then tries to finish the escape in new version
                        assert(current_escape.new_signer != 0, 'argent/null-owner');

                        let is_valid = self.is_valid_guardian_signature(execution_hash, signature);
                        assert(is_valid, 'argent/invalid-guardian-sig');
                        return; // valid
                    }
                    if selector == TRIGGER_ESCAPE_GUARDIAN_SELECTOR {
                        if !is_from_outside {
                            let current_attempts = self.owner_escape_attempts.read();
                            assert_valid_escape_parameters(current_attempts);
                            self.owner_escape_attempts.write(current_attempts + 1);
                        }
                        let mut calldata: Span<felt252> = call.calldata.span();
                        let new_guardian: felt252 = Serde::deserialize(ref calldata)
                            .expect('argent/invalid-calldata');
                        assert(calldata.is_empty(), 'argent/invalid-calldata');

                        if new_guardian == 0 {
                            assert(
                                self._guardian_backup.read() == 0, 'argent/backup-should-be-null'
                            );
                        }
                        self.assert_guardian_set();
                        let is_valid = self.is_valid_owner_signature(execution_hash, signature);
                        assert(is_valid, 'argent/invalid-owner-sig');
                        return; // valid
                    }
                    if selector == ESCAPE_GUARDIAN_SELECTOR {
                        if !is_from_outside {
                            let current_attempts = self.owner_escape_attempts.read();
                            assert_valid_escape_parameters(current_attempts);
                            self.owner_escape_attempts.write(current_attempts + 1);
                        }
                        assert(call.calldata.is_empty(), 'argent/invalid-calldata');
                        self.assert_guardian_set();
                        let current_escape = self._escape.read();

                        assert(
                            current_escape.escape_type == ESCAPE_TYPE_GUARDIAN,
                            'argent/invalid-escape'
                        );

                        // needed if user started escape in old cairo version and
                        // upgraded half way through, then tries to finish the escape in new version
                        if current_escape.new_signer == 0 {
                            assert(
                                self._guardian_backup.read() == 0, 'argent/backup-should-be-null'
                            );
                        }
                        let is_valid = self.is_valid_owner_signature(execution_hash, signature);
                        assert(is_valid, 'argent/invalid-owner-sig');
                        return; // valid
                    }
                    assert(selector != EXECUTE_AFTER_UPGRADE_SELECTOR, 'argent/forbidden-call');
                }
            } else {
                // make sure no call is to the account
                assert_no_self_call(calls, account_address);
            }

            self.assert_valid_span_signature(execution_hash, signature);
        }

        fn is_valid_span_signature(
            self: @ContractState, hash: felt252, signatures: Span<felt252>
        ) -> bool {
            let (owner_signature, guardian_signature) = split_signatures(signatures);
            let is_valid = self.is_valid_owner_signature(hash, owner_signature);
            if !is_valid {
                return false;
            }
            if self._guardian.read() == 0 {
                guardian_signature.is_empty()
            } else {
                self.is_valid_guardian_signature(hash, guardian_signature)
            }
        }

        fn assert_valid_span_signature(
            self: @ContractState, hash: felt252, signatures: Span<felt252>
        ) {
            let (owner_signature, guardian_signature) = split_signatures(signatures);
            let is_valid = self.is_valid_owner_signature(hash, owner_signature);
            assert(is_valid, 'argent/invalid-owner-sig');

            if self._guardian.read() == 0 {
                assert(guardian_signature.is_empty(), 'argent/invalid-guardian-sig');
            } else {
                assert(
                    self.is_valid_guardian_signature(hash, guardian_signature),
                    'argent/invalid-guardian-sig'
                );
            }
        }

        fn is_valid_owner_signature(
            self: @ContractState, hash: felt252, signature: Span<felt252>
        ) -> bool {
            if signature.len() != 2 {
                return false;
            }
            let signature_r = *signature[0];
            let signature_s = *signature[1];
            check_ecdsa_signature(hash, self._signer.read(), signature_r, signature_s)
        }

        fn is_valid_guardian_signature(
            self: @ContractState, hash: felt252, signature: Span<felt252>
        ) -> bool {
            if signature.len() != 2 {
                return false;
            }
            let signature_r = *signature[0];
            let signature_s = *signature[1];
            let is_valid = check_ecdsa_signature(
                hash, self._guardian.read(), signature_r, signature_s
            );
            if is_valid {
                true
            } else {
                check_ecdsa_signature(hash, self._guardian_backup.read(), signature_r, signature_s)
            }
        }

        /// The signature is the result of signing the message hash with the new owner private key
        /// The message hash is the result of hashing the array:
        /// [change_owner selector, chainid, contract address, old_owner]
        /// as specified here: https://docs.starknet.io/documentation/architecture_and_concepts/Hashing/hash-functions/#array_hashing
        fn assert_valid_new_owner(
            self: @ContractState, new_owner: felt252, signature_r: felt252, signature_s: felt252
        ) {
            assert(new_owner != 0, 'argent/null-owner');
            let chain_id = get_tx_info().unbox().chain_id;
            let mut message_hash = TupleSize4LegacyHash::hash(
                0, (CHANGE_OWNER_SELECTOR, chain_id, get_contract_address(), self._signer.read())
            );
            // We now need to hash message_hash with the size of the array: (change_owner selector, chainid, contract address, old_owner)
            // https://github.com/starkware-libs/cairo-lang/blob/b614d1867c64f3fb2cf4a4879348cfcf87c3a5a7/src/starkware/cairo/common/hash_state.py#L6
            message_hash = LegacyHashFelt252::hash(message_hash, 4);
            let is_valid = check_ecdsa_signature(message_hash, new_owner, signature_r, signature_s);
            assert(is_valid, 'argent/invalid-owner-sig');
        }

        #[inline(always)]
        fn reset_escape(ref self: ContractState) {
            let current_escape_status = get_escape_status(self._escape.read().ready_at);
            if current_escape_status == EscapeStatus::None(()) {
                return;
            }
            self._escape.write(Escape { ready_at: 0, escape_type: 0, new_signer: 0 });
            if current_escape_status != EscapeStatus::Expired(()) {
                self.emit(EscapeCanceled {});
            }
        }

        #[inline(always)]
        fn assert_guardian_set(self: @ContractState) {
            assert(self._guardian.read() != 0, 'argent/guardian-required');
        }

        #[inline(always)]
        fn reset_escape_attempts(ref self: ContractState) {
            self.owner_escape_attempts.write(0);
            self.guardian_escape_attempts.write(0);
        }
    }

    fn assert_valid_escape_parameters(attempts: u32) {
        let tx_info = get_tx_info().unbox();
        assert(tx_info.max_fee <= MAX_ESCAPE_MAX_FEE, 'argent/max-fee-too-high');
        assert(attempts < MAX_ESCAPE_ATTEMPTS, 'argent/max-escape-attempts');
    }

    fn split_signatures(full_signature: Span<felt252>) -> (Span<felt252>, Span<felt252>) {
        if full_signature.len() == 2 {
            return (full_signature, ArrayTrait::new().span());
        }
        assert(full_signature.len() == 4, 'argent/invalid-signature-length');
        let owner_signature = full_signature.slice(0, 2);
        let guardian_signature = full_signature.slice(2, 2);
        (owner_signature, guardian_signature)
    }

    fn get_escape_status(escape_ready_at: u64) -> EscapeStatus {
        if escape_ready_at == 0 {
            return EscapeStatus::None(());
        }

        let block_timestamp = get_block_timestamp();
        if block_timestamp < escape_ready_at {
            return EscapeStatus::NotReady(());
        }
        if escape_ready_at + ESCAPE_EXPIRY_PERIOD <= block_timestamp {
            return EscapeStatus::Expired(());
        }

        EscapeStatus::Ready(())
    }
}
