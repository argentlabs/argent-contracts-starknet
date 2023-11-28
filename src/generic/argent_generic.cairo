#[starknet::contract]
mod ArgentGenericAccount {
    use argent::common::{
        account::{
            IAccount, ERC165_ACCOUNT_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID_OLD_1, ERC165_ACCOUNT_INTERFACE_ID_OLD_2
        },
        asserts::{assert_correct_tx_version, assert_no_self_call, assert_only_protocol, assert_only_self,},
        calls::execute_multicall, version::Version,
        erc165::{
            IErc165, IErc165LibraryDispatcher, IErc165DispatcherTrait, ERC165_IERC165_INTERFACE_ID,
            ERC165_IERC165_INTERFACE_ID_OLD,
        },
        outside_execution::{
            OutsideExecution, IOutsideExecution, hash_outside_execution_message, ERC165_OUTSIDE_EXECUTION_INTERFACE_ID
        },
        upgrade::{IUpgradeable, IUpgradeableLibraryDispatcher, IUpgradeableDispatcherTrait}
    };
    use argent::generic::{
        signer_signature::{
            SignerSignature, SignerType, assert_valid_starknet_signature, assert_valid_ethereum_signature
        },
        interface::{IRecoveryAccount, IArgentMultisig}, recovery::{EscapeStatus, Escape, EscapeEnabled}
    };
    use core::array::SpanTrait;
    use starknet::{
        get_contract_address, VALIDATED, syscalls::replace_class_syscall, ClassHash, get_block_timestamp,
        get_caller_address, get_tx_info, account::Call
    };

    const NAME: felt252 = 'ArgentGenericAccount';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 0;
    const VERSION_PATCH: u8 = 1;
    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;
    /// Time it takes for the escape to become ready after being triggered

    #[storage]
    struct Storage {
        signer_list: LegacyMap<felt252, felt252>,
        threshold: usize,
        outside_nonces: LegacyMap<felt252, bool>,
        escape_enabled: EscapeEnabled,
        escape: Escape,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ThresholdUpdated: ThresholdUpdated,
        TransactionExecuted: TransactionExecuted,
        AccountUpgraded: AccountUpgraded,
        OwnerAdded: OwnerAdded,
        OwnerRemoved: OwnerRemoved,
        EscapeSignerTriggered: EscapeSignerTriggered,
        SignerEscaped: SignerEscaped,
    }

    /// @notice Emitted when the multisig threshold changes
    /// @param new_threshold New threshold
    #[derive(Drop, starknet::Event)]
    struct ThresholdUpdated {
        new_threshold: usize,
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

    /// @notice Emitted when the implementation of the account changes
    /// @param new_implementation The new implementation
    #[derive(Drop, starknet::Event)]
    struct AccountUpgraded {
        new_implementation: ClassHash
    }

    /// This event is part of an account discoverability standard, SNIP not yet created
    /// Emitted when an account owner is added, including when the account is created.
    #[derive(Drop, starknet::Event)]
    struct OwnerAdded {
        #[key]
        new_owner_guid: felt252,
    }

    /// This event is part of an account discoverability standard, SNIP not yet created
    /// Emitted when an an account owner is removed
    #[derive(Drop, starknet::Event)]
    struct OwnerRemoved {
        #[key]
        removed_owner_guid: felt252,
    }

    /// @notice Guardian escape was triggered by the owner
    /// @param ready_at when the escape can be completed
    /// @param target_signer the escaped signer address
    /// @param new_signer the new signer address to be set after the security period
    #[derive(Drop, starknet::Event)]
    struct EscapeSignerTriggered {
        ready_at: u64,
        target_signer: felt252,
        new_signer: felt252
    }

    /// @notice Signer escape was completed and there is a new signer
    /// @param target_signer the escaped signer address
    /// @param new_signer the new signer address
    #[derive(Drop, starknet::Event)]
    struct SignerEscaped {
        target_signer: felt252,
        new_signer: felt252
    }

    #[constructor]
    fn constructor(ref self: ContractState, new_threshold: usize, signers: Array<felt252>) {
        let new_signers_count = signers.len();
        assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

        self.add_signers_inner(signers.span(), last_signer: 0);
        self.threshold.write(new_threshold);

        self.emit(ThresholdUpdated { new_threshold });

        let mut signers_added = signers.span();
        loop {
            match signers_added.pop_front() {
                Option::Some(added_signer) => { self.emit(OwnerAdded { new_owner_guid: *added_signer }); },
                Option::None => { break; }
            };
        };
    }

    #[external(v0)]
    impl Account of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            assert_only_protocol();
            let tx_info = get_tx_info().unbox();
            // validate version
            assert_correct_tx_version(tx_info.version);
            // validate calls
            self.assert_valid_calls(calls.span());
            // validate signatures
            self.assert_valid_signatures(calls.span(), tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert_only_protocol();
            // execute calls
            let retdata = execute_multicall(calls.span());
            // emit event
            let tx_info = get_tx_info().unbox();
            let hash = tx_info.transaction_hash;
            let response = retdata.span();
            self.emit(TransactionExecuted { hash, response });
            retdata
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            let threshold = self.threshold.read();
            if self.is_valid_signature_with_conditions(hash, threshold, 0_felt252, signature.span()) {
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
                outside_execution.execute_after < block_timestamp && block_timestamp < outside_execution.execute_before,
                'argent/invalid-timestamp'
            );
            let nonce = outside_execution.nonce;
            assert(!self.outside_nonces.read(nonce), 'argent/duplicated-outside-nonce');

            let outside_tx_hash = hash_outside_execution_message(@outside_execution);

            let calls = outside_execution.calls;

            // validate calls
            self.assert_valid_calls(calls);
            // validate signatures
            self.assert_valid_signatures(calls, outside_tx_hash, signature.span());

            // Effects
            self.outside_nonces.write(nonce, true);

            // Interactions
            let retdata = execute_multicall(calls);

            let hash = outside_tx_hash;
            let response = retdata.span();
            self.emit(TransactionExecuted { hash, response });
            retdata
        }

        fn get_outside_execution_message_hash(self: @ContractState, outside_execution: OutsideExecution) -> felt252 {
            hash_outside_execution_message(@outside_execution)
        }

        fn is_valid_outside_execution_nonce(self: @ContractState, nonce: felt252) -> bool {
            !self.outside_nonces.read(nonce)
        }
    }

    #[external(v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        /// @dev Can be called by the account to upgrade the implementation
        fn upgrade(ref self: ContractState, new_implementation: ClassHash, calldata: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            let supports_interface = IErc165LibraryDispatcher { class_hash: new_implementation }
                .supports_interface(ERC165_ACCOUNT_INTERFACE_ID);
            assert(supports_interface, 'argent/invalid-implementation');

            replace_class_syscall(new_implementation).unwrap();
            self.emit(AccountUpgraded { new_implementation });

            IUpgradeableLibraryDispatcher { class_hash: new_implementation }.execute_after_upgrade(calldata)
        }

        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            // Check basic invariants
            assert_valid_threshold_and_signers_count(self.threshold.read(), self.get_signers_len());

            assert(data.len() == 0, 'argent/unexpected-data');
            array![]
        }
    }

    #[external(v0)]
    impl ArgentMultisigImpl of IArgentMultisig<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            panic_with_felt252('argent/declare-not-available') // Not implemented yet
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            threshold: usize,
            signers: Array<felt252>
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            assert_correct_tx_version(tx_info.version);

            let mut signature = tx_info.signature;
            let mut parsed_signatures: Array<SignerSignature> = Serde::deserialize(ref signature)
                .expect('argent/undeserializable-sig');
            assert(signature.is_empty(), 'argent/signature-not-empty');
            // TODO AS LONG AS FIRST SIGNATURE IS OK, DEPLOY (this is prob wrong, we should loop)
            assert(parsed_signatures.len() >= 1, 'argent/invalid-signature-length');

            let signer_sig = *parsed_signatures.at(0);
            let is_valid = self
                .is_valid_signer_signature(
                    tx_info.transaction_hash,
                    signer: signer_sig.signer,
                    signer_type: signer_sig.signer_type,
                    signature: array![].span(),
                );
            assert(is_valid, 'argent/invalid-signature');

            VALIDATED
        }

        fn change_threshold(ref self: ContractState, new_threshold: usize) {
            assert_only_self();
            assert(new_threshold != self.threshold.read(), 'argent/same-threshold');
            let new_signers_count = self.get_signers_len();

            assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);
            self.threshold.write(new_threshold);
            self.emit(ThresholdUpdated { new_threshold });
        }

        fn add_signers(ref self: ContractState, new_threshold: usize, signers_to_add: Array<felt252>) {
            assert_only_self();
            let (signers_len, last_signer) = self.load();
            let previous_threshold = self.threshold.read();

            let new_signers_count = signers_len + signers_to_add.len();
            assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);
            self.add_signers_inner(signers_to_add.span(), last_signer);
            self.threshold.write(new_threshold);

            if previous_threshold != new_threshold {
                self.emit(ThresholdUpdated { new_threshold });
            }

            let mut signers_added = signers_to_add.span();
            loop {
                match signers_added.pop_front() {
                    Option::Some(added_signer) => { self.emit(OwnerAdded { new_owner_guid: *added_signer }); },
                    Option::None => { break; }
                };
            };
        }

        fn remove_signers(ref self: ContractState, new_threshold: usize, signers_to_remove: Array<felt252>) {
            assert_only_self();
            let (signers_len, last_signer) = self.load();
            let previous_threshold = self.threshold.read();

            let new_signers_count = signers_len - signers_to_remove.len();
            assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

            self.remove_signers_inner(signers_to_remove.span(), last_signer);
            self.threshold.write(new_threshold);

            if previous_threshold != new_threshold {
                self.emit(ThresholdUpdated { new_threshold });
            }

            let mut signers_removed = signers_to_remove.span();
            loop {
                match signers_removed.pop_front() {
                    Option::Some(removed_signer) => {
                        self.emit(OwnerRemoved { removed_owner_guid: *removed_signer });
                    },
                    Option::None => { break; }
                };
            };
        }

        fn reorder_signers(ref self: ContractState, new_signer_order: Array<felt252>) {
            assert_only_self();
            let (signers_len, last_signer) = self.load();
            assert(new_signer_order.len() == signers_len, 'argent/too-short');
            let mut sself = @self;
            let mut signers_to_check = new_signer_order.span();
            loop {
                match signers_to_check.pop_front() {
                    Option::Some(signer) => {
                        assert(sself.is_signer_using_last(*signer, last_signer), 'argent/unknown-signer');
                    },
                    Option::None => { break; }
                };
            };

            let mut signers_to_reorder = new_signer_order.span();
            let mut prev_signer = 0;
            loop {
                match signers_to_reorder.pop_front() {
                    Option::Some(signer) => {
                        self.signer_list.write(prev_signer, *signer);
                        prev_signer = *signer;
                    },
                    Option::None => {
                        self.signer_list.write(prev_signer, 0);
                        break;
                    }
                };
            };
        }

        fn replace_signer(ref self: ContractState, signer_to_remove: felt252, signer_to_add: felt252) {
            assert_only_self();
            let (new_signers_count, last_signer) = self.load();

            self.replace_signer_inner(signer_to_remove, signer_to_add, last_signer);

            self.emit(OwnerRemoved { removed_owner_guid: signer_to_remove });
            self.emit(OwnerAdded { new_owner_guid: signer_to_add });
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
        }

        fn get_threshold(self: @ContractState) -> usize {
            self.threshold.read()
        }

        fn get_signers(self: @ContractState) -> Array<felt252> {
            self.get_signers_inner()
        }

        fn is_signer(self: @ContractState, signer: felt252) -> bool {
            self.is_signer_inner(signer)
        }

        // TODO Needs to update the interface
        fn is_valid_signer_signature(
            self: @ContractState, hash: felt252, signer: felt252, signer_type: SignerType, signature: Span<felt252>
        ) -> bool {
            self.is_valid_signer_signature_inner(hash, signer, signer_type)
        }
    }

    #[external(v0)]
    impl RecoveryAccountImpl of IRecoveryAccount<ContractState> {
        fn toggle_escape(ref self: ContractState, is_enabled: bool, security_period: u64, expiry_period: u64) {
            assert_only_self();
            // cannot toggle escape if there is an ongoing escape 
            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            let current_escaped_signer = current_escape.target_signer;
            assert(
                current_escaped_signer == 0 || current_escape_status == EscapeStatus::Expired, 'argent/ongoing-escape'
            );

            if (is_enabled) {
                assert(security_period != 0 && expiry_period != 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: 1, security_period, expiry_period });
            } else {
                assert(escape_config.is_enabled == 1, 'argent/escape-disabled');
                assert(security_period == 0 && expiry_period == 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: 0, security_period, expiry_period });
            }
        }

        fn trigger_escape_signer(ref self: ContractState, target_signer: felt252, new_signer: felt252) {
            assert_only_self();

            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            let current_escaped_signer = current_escape.target_signer;
            if (current_escaped_signer != 0 && current_escape_status == EscapeStatus::Ready) {
                // can only override an escape with a target signer of lower priority than the current one
                assert(self.is_signer_before(current_escaped_signer, target_signer), 'argent/cannot-override-escape');
            }
            let ready_at = get_block_timestamp() + escape_config.security_period;
            let escape = Escape { ready_at, target_signer, new_signer };
            self.escape.write(escape);
            self.emit(EscapeSignerTriggered { ready_at, target_signer, new_signer });
        }

        fn escape_signer(ref self: ContractState) {
            assert_only_self();

            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            // replace signer 
            let (_, last_signer) = self.load();
            self.replace_signer_inner(current_escape.target_signer, current_escape.new_signer, last_signer);
            self
                .emit(
                    SignerEscaped { target_signer: current_escape.target_signer, new_signer: current_escape.new_signer }
                );
            self.emit(OwnerRemoved { removed_owner_guid: current_escape.target_signer });
            self.emit(OwnerAdded { new_owner_guid: current_escape.new_signer });

            // clear escape
            self.escape.write(Escape { ready_at: 0, target_signer: 0, new_signer: 0 });
        }

        fn cancel_escape(ref self: ContractState) {
            assert_only_self();
            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status != EscapeStatus::None, 'argent/invalid-escape');
            self.escape.write(Escape { ready_at: 0, target_signer: 0, new_signer: 0 });
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

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls(self: @ContractState, calls: Span<Call>) {
            let account_address = get_contract_address();
            if calls.len() == 1 {
                let call = calls.at(0);
                if *call.to == account_address {
                    // This should only be called after an upgrade, never directly
                    assert(*call.selector != selector!("execute_after_upgrade"), 'argent/forbidden-call');
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
            // get threshold
            let threshold = self.threshold.read();
            let first_call = calls.at(0);
            if (*first_call.to == get_contract_address()) {
                if (*first_call.selector == selector!("trigger_escape_signer")) {
                    // check we can do recovery
                    let escape_enabled = self.escape_enabled.read();
                    assert(escape_enabled.is_enabled == 1 && threshold > 1, 'argent/recovery-unavailable');
                    // get escaped signer
                    let calldata: Span<felt252> = first_call.calldata.span();
                    let escaped_signer = calldata.at(0);
                    // check it is a valid signer
                    let is_signer = self.is_signer_inner(*escaped_signer);
                    assert(is_signer, 'argent/escaped-not-signer');
                    // check signatures
                    let valid = self
                        .is_valid_signature_with_conditions(execution_hash, threshold - 1, *escaped_signer, signature);
                    assert(valid, 'argent/invalid-signature');
                    return;
                } else if (*first_call.selector == selector!("escape_signer")) {
                    // check we can do recovery
                    let escape_enabled = self.escape_enabled.read();
                    assert(escape_enabled.is_enabled == 1 && threshold > 1, 'argent/recovery-unavailable');
                    // get escaped signer
                    let calldata: Span<felt252> = first_call.calldata.span();
                    let escaped_signer = calldata.at(0);
                    // check signatures
                    let valid = self
                        .is_valid_signature_with_conditions(execution_hash, threshold - 1, *escaped_signer, signature);
                    assert(valid, 'argent/invalid-signature');
                    return;
                }
            }

            let valid = self.is_valid_signature_with_conditions(execution_hash, threshold, 0_felt252, signature);
            assert(valid, 'argent/invalid-signature');
        }

        fn is_valid_signature_with_conditions(
            self: @ContractState,
            hash: felt252,
            expected_length: u32,
            excluded_signer: felt252,
            mut signature: Span<felt252>
        ) -> bool {
            let mut signer_signatures: Array<SignerSignature> = Serde::deserialize(ref signature)
                .expect('argent/undeserializable-sig');
            assert(signer_signatures.len() == expected_length, 'argent/signature-invalid-length');
            assert(signature.is_empty(), 'argent/signature-not-empty');

            let mut last_signer: u256 = 0;
            loop {
                match signer_signatures.pop_front() {
                    Option::Some(signer_sig) => {
                        assert(signer_sig.signer != excluded_signer, 'argent/unauthorised_signer');
                        let signer_uint: u256 = signer_sig.signer.into();
                        assert(signer_uint > last_signer, 'argent/signatures-not-sorted');
                        let is_valid = self
                            .is_valid_signer_signature(
                                hash,
                                signer: signer_sig.signer,
                                signer_type: signer_sig.signer_type,
                                signature: array![].span(),
                            );
                        if !is_valid {
                            break false;
                        }
                        last_signer = signer_uint;
                    },
                    Option::None => { break true; }
                };
            }
        }

        fn is_valid_signer_signature_inner(
            self: @ContractState, hash: felt252, signer: felt252, signer_type: SignerType
        ) -> bool {
            let is_signer = self.is_signer_inner(signer);
            assert(is_signer, 'argent/not-a-signer');
            match signer_type {
                SignerType::Starknet(signature) => {
                    assert_valid_starknet_signature(hash, signer, signature);
                    true
                },
                SignerType::Secp256k1(signature) => {
                    assert_valid_ethereum_signature(hash, signer, signature);
                    true
                },
                SignerType::Webauthn => false,
                SignerType::Secp256r1 => false,
            }
        }
    }

    fn assert_valid_threshold_and_signers_count(threshold: usize, signers_len: usize) {
        assert(threshold != 0, 'argent/invalid-threshold');
        assert(signers_len != 0, 'argent/invalid-signers-len');
        assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        assert(threshold <= signers_len, 'argent/bad-threshold');
    }

    #[generate_trait]
    impl MultisigStorageImpl of MultisigStorage {
        // Constant computation cost if `signer` is in fact in the list AND it's not the last one.
        // Otherwise cost increases with the list size
        fn is_signer_inner(self: @ContractState, signer: felt252) -> bool {
            if signer == 0 {
                return false;
            }
            let next_signer = self.signer_list.read(signer);
            if next_signer != 0 {
                return true;
            }
            // check if its the latest
            let last_signer = self.find_last_signer();

            last_signer == signer
        }

        // Optimized version of `is_signer` with constant compute cost. To use when you know the last signer
        fn is_signer_using_last(self: @ContractState, signer: felt252, last_signer: felt252) -> bool {
            if signer == 0 {
                return false;
            }

            let next_signer = self.signer_list.read(signer);
            if next_signer != 0 {
                return true;
            }

            last_signer == signer
        }

        // Return the last signer or zero if no signers. Cost increases with the list size
        fn find_last_signer(self: @ContractState) -> felt252 {
            let mut current_signer = self.signer_list.read(0);
            loop {
                let next_signer = self.signer_list.read(current_signer);
                if next_signer == 0 {
                    break current_signer;
                }
                current_signer = next_signer;
            }
        }

        // Returns the signer before `signer_after` or 0 if the signer is the first one. 
        // Reverts if `signer_after` is not found
        // Cost increases with the list size
        fn find_signer_before(self: @ContractState, signer_after: felt252) -> felt252 {
            let mut current_signer = 0;
            loop {
                let next_signer = self.signer_list.read(current_signer);
                assert(next_signer != 0, 'argent/cant-find-signer-before');

                if next_signer == signer_after {
                    break current_signer;
                }
                current_signer = next_signer;
            }
        }

        // Returns true if `first_signer` is before `second_signer` in the signer list.
        fn is_signer_before(self: @ContractState, first_signer: felt252, second_signer: felt252) -> bool {
            let mut is_before: bool = false;
            let mut current_signer = first_signer;
            loop {
                let next_signer = self.signer_list.read(current_signer);
                if (next_signer == 0_felt252) {
                    break;
                }
                if (next_signer == second_signer) {
                    is_before = true;
                    break;
                }
                current_signer = next_signer;
            };
            return is_before;
        }

        fn add_signers_inner(ref self: ContractState, mut signers_to_add: Span<felt252>, last_signer: felt252) {
            match signers_to_add.pop_front() {
                Option::Some(signer_ref) => {
                    let signer = *signer_ref;
                    assert(signer != 0, 'argent/invalid-zero-signer');

                    let current_signer_status = self.is_signer_using_last(signer, last_signer);
                    assert(!current_signer_status, 'argent/already-a-signer');

                    // Signers are added at the end of the list
                    self.signer_list.write(last_signer, signer);

                    self.add_signers_inner(signers_to_add, last_signer: signer);
                },
                Option::None => (),
            }
        }

        fn remove_signers_inner(ref self: ContractState, mut signers_to_remove: Span<felt252>, last_signer: felt252) {
            match signers_to_remove.pop_front() {
                Option::Some(signer_ref) => {
                    let signer = *signer_ref;
                    let current_signer_status = self.is_signer_using_last(signer, last_signer);
                    assert(current_signer_status, 'argent/not-a-signer');

                    // Signer pointer set to 0, Previous pointer set to the next in the list

                    let previous_signer = self.find_signer_before(signer);
                    let next_signer = self.signer_list.read(signer);

                    self.signer_list.write(previous_signer, next_signer);

                    if next_signer == 0 {
                        // Removing the last item
                        self.remove_signers_inner(signers_to_remove, last_signer: previous_signer);
                    } else {
                        // Removing an item in the middle
                        self.signer_list.write(signer, 0);
                        self.remove_signers_inner(signers_to_remove, last_signer);
                    }
                },
                Option::None => (),
            }
        }

        fn replace_signer_inner(
            ref self: ContractState, signer_to_remove: felt252, signer_to_add: felt252, last_signer: felt252
        ) {
            assert(signer_to_add != 0, 'argent/invalid-zero-signer');

            let signer_to_add_status = self.is_signer_using_last(signer_to_add, last_signer);
            assert(!signer_to_add_status, 'argent/already-a-signer');

            let signer_to_remove_status = self.is_signer_using_last(signer_to_remove, last_signer);
            assert(signer_to_remove_status, 'argent/not-a-signer');

            // removed signer will point to 0
            // previous signer will point to the new one
            // new signer will point to the next one
            let previous_signer = self.find_signer_before(signer_to_remove);
            let next_signer = self.signer_list.read(signer_to_remove);

            self.signer_list.write(signer_to_remove, 0);
            self.signer_list.write(previous_signer, signer_to_add);
            self.signer_list.write(signer_to_add, next_signer);
        }

        // Returns the number of signers and the last signer (or zero if the list is empty). Cost increases with the list size
        // returns (signers_len, last_signer)
        fn load(self: @ContractState) -> (usize, felt252) {
            let mut current_signer = 0;
            let mut size = 0;
            loop {
                let next_signer = self.signer_list.read(current_signer);
                if next_signer == 0 {
                    break (size, current_signer);
                }
                current_signer = next_signer;
                size += 1;
            }
        }

        // Returns the number of signers. Cost increases with the list size
        fn get_signers_len(self: @ContractState) -> usize {
            let mut current_signer = self.signer_list.read(0);
            let mut size = 0;
            loop {
                if current_signer == 0 {
                    break size;
                }
                current_signer = self.signer_list.read(current_signer);
                size += 1;
            }
        }

        fn get_signers_inner(self: @ContractState) -> Array<felt252> {
            let mut current_signer = self.signer_list.read(0);
            let mut signers = array![];
            loop {
                if current_signer == 0 {
                    // Can't break signers atm because "variable was previously moved"
                    break;
                }
                signers.append(current_signer);
                current_signer = self.signer_list.read(current_signer);
            };
            signers
        }
    }

    fn get_escape_status(escape_ready_at: u64, expiry_period: u64) -> EscapeStatus {
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
