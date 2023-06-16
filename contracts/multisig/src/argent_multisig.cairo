use lib::{OutsideExecution, Version};

#[starknet::interface]
trait IExecuteFromOutside<TContractState> {
    fn execute_from_outside(
        ref self: TContractState, outside_execution: OutsideExecution, signature: Array<felt252>
    ) -> Array<Span<felt252>>;

    fn get_outside_execution_message_hash(
        self: @TContractState, outside_execution: OutsideExecution
    ) -> felt252;
}

#[starknet::interface]
trait IArgentMultisig<TContractState> {
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<felt252>
    ) -> felt252;
    // External
    fn change_threshold(ref self: TContractState, new_threshold: usize);
    fn add_signers(ref self: TContractState, new_threshold: usize, signers_to_add: Array<felt252>);
    fn remove_signers(
        ref self: TContractState, new_threshold: usize, signers_to_remove: Array<felt252>
    );
    fn replace_signer(ref self: TContractState, signer_to_remove: felt252, signer_to_add: felt252);
    // Views
    fn get_name(self: @TContractState) -> felt252;
    fn getName(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
    fn getVersion(self: @TContractState) -> felt252;
    fn get_threshold(self: @TContractState) -> usize;
    fn get_signers(self: @TContractState) -> Array<felt252>;
    fn is_signer(self: @TContractState, signer: felt252) -> bool;
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
    fn supportsInterface(self: @TContractState, interface_id: felt252) -> felt252;
    fn assert_valid_signer_signature(
        self: @TContractState,
        hash: felt252,
        signer: felt252,
        signature_r: felt252,
        signature_s: felt252
    );
    fn is_valid_signer_signature(
        self: @TContractState,
        hash: felt252,
        signer: felt252,
        signature_r: felt252,
        signature_s: felt252
    ) -> bool;

    fn is_valid_signature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
    fn isValidSignature(
        self: @TContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252;
}

#[starknet::contract]
mod ArgentMultisig {
    use array::{ArrayTrait, SpanTrait};
    use box::BoxTrait;
    use ecdsa::check_ecdsa_signature;
    use option::OptionTrait;
    use traits::Into;
    use zeroable::Zeroable;
    use starknet::{
        get_contract_address, ContractAddressIntoFelt252, VALIDATED,
        syscalls::replace_class_syscall, ClassHash, class_hash_const, get_block_timestamp,
        get_caller_address, get_tx_info
    };
    use starknet::account::{Call};

    use lib::{
        AccountContract, assert_only_self, assert_no_self_call, assert_correct_tx_version,
        assert_caller_is_null, execute_multicall, Version, IErc165LibraryDispatcher,
        IErc165DispatcherTrait, OutsideExecution, hash_outside_execution_message,
        ERC165_IERC165_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID_OLD_1,
        ERC165_ACCOUNT_INTERFACE_ID_OLD_2, ERC1271_VALIDATED, IAccountUpgrade,
        IAccountUpgradeLibraryDispatcher, IAccountUpgradeDispatcherTrait
    };
    use multisig::{deserialize_array_signer_signature, SignerSignature};

    const EXECUTE_AFTER_UPGRADE_SELECTOR: felt252 =
        738349667340360233096752603318170676063569407717437256101137432051386874767; // starknet_keccak('execute_after_upgrade')

    const NAME: felt252 = 'ArgentMultisig';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 1;
    const VERSION_PATCH: u8 = 0;
    const VERSION_COMPAT: felt252 = '0.1.0';
    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Events                                           //
    ////////////////////////////////////////////////////////////////////////////////////////////////
    #[storage]
    struct Storage {
        signer_list: LegacyMap<felt252, felt252>,
        threshold: usize,
        outside_nonces: LegacyMap<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ConfigurationUpdated: ConfigurationUpdated,
        TransactionExecuted: TransactionExecuted,
        AccountUpgraded: AccountUpgraded
    }
    /// @notice Emitted when the multisig configuration changes
    /// @param new_threshold New threshold
    /// @param new_signers_count The number of signers after the update
    /// @param added_signers Signers added in this update
    /// @param removed_signers Signers removed by this update
    #[derive(Drop, starknet::Event)]
    struct ConfigurationUpdated {
        new_threshold: usize,
        new_signers_count: usize,
        added_signers: Array<felt252>,
        removed_signers: Array<felt252>
    }

    /// @notice Emitted when the account executes a transaction
    /// @param hash The transaction hash
    /// @param response The data returned by the methods called
    #[derive(Drop, starknet::Event)]
    struct TransactionExecuted {
        hash: felt252,
        response: Span<Span<felt252>>
    }

    /// @notice Emitted when the implementation of the account changes
    /// @param new_implementation The new implementation
    #[derive(Drop, starknet::Event)]
    struct AccountUpgraded {
        new_implementation: ClassHash
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                     Constructor                                            //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, threshold: usize, signers: Array<felt252>) {
        let signers_len = signers.len();
        assert_valid_threshold_and_signers_count(threshold, signers_len);

        self.add_signers(signers.span(), last_signer: 0);
        self.set_threshold(threshold);

        self
            .emit(
                Event::ConfigurationUpdated(
                    ConfigurationUpdated {
                        new_threshold: threshold,
                        new_signers_count: signers_len,
                        added_signers: signers,
                        removed_signers: ArrayTrait::new()
                    }
                )
            );
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                     External functions                                     //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[external(v0)]
    impl AccountContractImpl of AccountContract<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            assert_caller_is_null();
            let tx_info = get_tx_info().unbox();
            assert_valid_calls_and_signature(
                @self, calls.span(), tx_info.transaction_hash, tx_info.signature
            );
            VALIDATED
        }

        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            panic_with_felt252('argent/declare-not-available') // Not implemented yet
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert_caller_is_null();
            let tx_info = starknet::get_tx_info().unbox();
            assert_correct_tx_version(tx_info.version);

            let retdata = execute_multicall(calls.span());
            self
                .emit(
                    Event::TransactionExecuted(
                        TransactionExecuted {
                            hash: tx_info.transaction_hash, response: retdata.span()
                        }
                    )
                );
            retdata
        }
    }


    #[external(v0)]
    impl ArgentMultisigImpl of super::IArgentMultisig<ContractState> {
        /// Self deployment meaning that the multisig pays for it's own deployment fee.
        /// In this scenario the multisig only requires the signature from one of the owners.
        /// This allows for better UX. UI must make clear that the funds are not safe from a bad signer until the deployment happens.
        /// @dev Validates signature for self deployment.
        /// @dev If signers can't be trusted, it's recommended to start with a 1:1 multisig and add other signers late
        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            threshold: usize,
            signers: Array<felt252>
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            assert_correct_tx_version(tx_info.version);

            let parsed_signatures = deserialize_array_signer_signature(tx_info.signature)
                .expect('argent/invalid-signature-length');
            assert(parsed_signatures.len() == 1, 'argent/invalid-signature-length');

            let signer_sig = *parsed_signatures.at(0);
            let valid_signer_signature = is_valid_signer_signature_rename(
                self,
                tx_info.transaction_hash,
                signer_sig.signer,
                signer_sig.signature_r,
                signer_sig.signature_s
            );
            assert(valid_signer_signature, 'argent/invalid-signature');
            VALIDATED
        }

        /// @dev Change threshold
        /// @param new_threshold New threshold
        fn change_threshold(ref self: ContractState, new_threshold: usize) {
            assert_only_self();
            let signers_len = self.get_signers_len();

            assert_valid_threshold_and_signers_count(new_threshold, signers_len);
            self.set_threshold(new_threshold);

            self
                .emit(
                    Event::ConfigurationUpdated(
                        ConfigurationUpdated {
                            new_threshold: new_threshold,
                            new_signers_count: signers_len,
                            added_signers: ArrayTrait::new(),
                            removed_signers: ArrayTrait::new()
                        }
                    )
                );
        }


        /// @dev Adds new signers to the account, additionally sets a new threshold
        /// @param new_threshold New threshold
        /// @param signers_to_add An array with all the signers to add
        /// @dev will revert when trying to add a user already in the list
        fn add_signers(
            ref self: ContractState, new_threshold: usize, signers_to_add: Array<felt252>
        ) {
            assert_only_self();
            let (signers_len, last_signer) = self.load();

            let new_signers_len = signers_len + signers_to_add.len();
            assert_valid_threshold_and_signers_count(new_threshold, new_signers_len);

            self.add_signers(signers_to_add.span(), last_signer);
            self.set_threshold(new_threshold);

            self
                .emit(
                    Event::ConfigurationUpdated(
                        ConfigurationUpdated {
                            new_threshold: new_threshold,
                            new_signers_count: new_signers_len,
                            added_signers: signers_to_add,
                            removed_signers: ArrayTrait::new()
                        }
                    )
                );
        }

        /// @dev Removes account signers, additionally sets a new threshold
        /// @param new_threshold New threshold
        /// @param signers_to_remove Should contain only current signers, otherwise it will revert
        fn remove_signers(
            ref self: ContractState, new_threshold: usize, signers_to_remove: Array<felt252>
        ) {
            assert_only_self();
            let (signers_len, last_signer) = self.load();

            let new_signers_len = signers_len - signers_to_remove.len();
            assert_valid_threshold_and_signers_count(new_threshold, new_signers_len);

            self.remove_signers(signers_to_remove.span(), last_signer);
            self.set_threshold(new_threshold);

            self
                .emit(
                    Event::ConfigurationUpdated(
                        ConfigurationUpdated {
                            new_threshold: new_threshold,
                            new_signers_count: new_signers_len,
                            added_signers: ArrayTrait::new(),
                            removed_signers: signers_to_remove
                        }
                    )
                );
        }

        /// @dev Replace one signer with a different one
        /// @param signer_to_remove Signer to remove
        /// @param signer_to_add Signer to add
        fn replace_signer(
            ref self: ContractState, signer_to_remove: felt252, signer_to_add: felt252
        ) {
            assert_only_self();
            let (signers_len, last_signer) = self.load();

            self.replace_signer(signer_to_remove, signer_to_add, last_signer);

            let mut added_signers = ArrayTrait::new();
            added_signers.append(signer_to_add);

            let mut removed_signer = ArrayTrait::new();
            removed_signer.append(signer_to_remove);
            self
                .emit(
                    Event::ConfigurationUpdated(
                        ConfigurationUpdated {
                            new_threshold: self.get_threshold(),
                            new_signers_count: signers_len,
                            added_signers: added_signers,
                            removed_signers: removed_signer
                        }
                    )
                );
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////
        //                                       View functions                                       //
        ////////////////////////////////////////////////////////////////////////////////////////////////

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        /// Deprecated method for compatibility reasons
        fn getName(self: @ContractState, ) -> felt252 {
            NAME
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
        }

        /// Deprecated method for compatibility reasons
        fn getVersion(self: @ContractState) -> felt252 {
            VERSION_COMPAT
        }

        /// @dev Returns the threshold, the number of signers required to control this account
        fn get_threshold(self: @ContractState) -> usize {
            self.get_threshold()
        }

        fn get_signers(self: @ContractState) -> Array<felt252> {
            self.get_signers()
        }

        fn is_signer(self: @ContractState, signer: felt252) -> bool {
            self.is_signer(signer)
        }

        // ERC165
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            if interface_id == ERC165_IERC165_INTERFACE_ID {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID_OLD_1 {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID_OLD_2 {
                true
            } else {
                false
            }
        }

        /// Deprecated method for compatibility reasons
        fn supportsInterface(self: @ContractState, interface_id: felt252) -> felt252 {
            if interface_id == ERC165_IERC165_INTERFACE_ID {
                1
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID {
                1
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID_OLD_1 {
                1
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID_OLD_2 {
                1
            } else {
                0
            }
        }

        /// Asserts that the given signature is a valid signature from one of the multisig owners
        /// Deprecated method for compatibility reasons
        fn assert_valid_signer_signature(
            self: @ContractState,
            hash: felt252,
            signer: felt252,
            signature_r: felt252,
            signature_s: felt252
        ) {
            let is_valid = is_valid_signer_signature_rename(
                self, hash, signer, signature_r, signature_s
            );
            assert(is_valid, 'argent/invalid-signature');
        }

        /// Checks if a given signature is a valid signature from one of the multisig owners
        fn is_valid_signer_signature(
            self: @ContractState,
            hash: felt252,
            signer: felt252,
            signature_r: felt252,
            signature_s: felt252
        ) -> bool {
            is_valid_signer_signature_rename(self, hash, signer, signature_r, signature_s)
        }

        // ERC1271
        fn is_valid_signature(
            self: @ContractState, hash: felt252, signatures: Array<felt252>
        ) -> felt252 {
            is_valid_signature_rename(self, hash, signatures)
        }

        /// Deprecated method for compatibility reasons
        fn isValidSignature(
            self: @ContractState, hash: felt252, signatures: Array<felt252>
        ) -> felt252 {
            is_valid_signature_rename(self, hash, signatures)
        }
    }

    // ERC1271
    fn is_valid_signature_rename(
        self: @ContractState, hash: felt252, signatures: Array<felt252>
    ) -> felt252 {
        if is_valid_span_signature(self, hash, signatures.span()) {
            ERC1271_VALIDATED
        } else {
            0
        }
    }

    fn is_valid_signer_signature_rename(
        self: @ContractState,
        hash: felt252,
        signer: felt252,
        signature_r: felt252,
        signature_s: felt252
    ) -> bool {
        let is_signer = self.is_signer(signer);
        assert(is_signer, 'argent/not-a-signer');
        check_ecdsa_signature(hash, signer, signature_r, signature_s)
    }

    #[external(v0)]
    impl ArgentUpgradeAccountImpl of IAccountUpgrade<ContractState> {
        /// @dev Can be called by the account to upgrade the implementation
        /// @param calldata Will be passed to the new implementation `execute_after_upgrade` method
        /// @param implementation class hash of the new implementation 
        /// @return retdata The data returned by `execute_after_upgrade`
        fn upgrade(
            ref self: ContractState, new_implementation: ClassHash, calldata: Array<felt252>
        ) -> Array<felt252> {
            assert_only_self();

            let supports_interface = IErc165LibraryDispatcher {
                class_hash: new_implementation
            }.supports_interface(ERC165_ACCOUNT_INTERFACE_ID);
            assert(supports_interface, 'argent/invalid-implementation');

            replace_class_syscall(new_implementation).unwrap_syscall();
            self.emit(Event::AccountUpgraded(AccountUpgraded { new_implementation }));

            IAccountUpgradeLibraryDispatcher {
                class_hash: new_implementation
            }.execute_after_upgrade(calldata)
        }

        /// see `IUpgradeTarget`
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            // Check basic invariants
            assert_valid_threshold_and_signers_count(self.get_threshold(), self.get_signers_len());

            assert(data.len() == 0, 'argent/unexpected-data');
            ArrayTrait::new()
        }
    }

    impl ExecuteFromOutsideImpl of super::IExecuteFromOutside<ContractState> {
        /// @notice This method allows anyone to submit a transaction on behalf of the account as long as they have the relevant signatures
        /// @param outside_execution The parameters of the transaction to execute
        /// @param signature A valid signature on the Eip712 message encoding of `outside_execution`
        /// @notice This method allows reentrancy. A call to `__execute__` or `execute_from_outside` can trigger another nested transaction to `execute_from_outside`.
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
            assert(!self.get_outside_nonce(nonce), 'argent/duplicated-outside-nonce');

            let outside_tx_hash = hash_outside_execution_message(@outside_execution);

            let calls = outside_execution.calls;

            assert_valid_calls_and_signature(@self, calls, outside_tx_hash, signature.span());

            // Effects
            self.set_outside_nonce(nonce, true);

            // Interactions
            let retdata = execute_multicall(calls);
            self
                .emit(
                    Event::TransactionExecuted(
                        TransactionExecuted { hash: outside_tx_hash, response: retdata.span() }
                    )
                );
            retdata
        }


        /// Get the message hash for some `OutsideExecution` following Eip712. Can be used to know what needs to be signed
        fn get_outside_execution_message_hash(
            self: @ContractState, outside_execution: OutsideExecution
        ) -> felt252 {
            return hash_outside_execution_message(@outside_execution);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                   Internal Functions                                       //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    fn assert_valid_calls_and_signature(
        self: @ContractState, calls: Span<Call>, execution_hash: felt252, signature: Span<felt252>
    ) {
        let account_address = get_contract_address();
        let tx_info = get_tx_info().unbox();
        assert_correct_tx_version(tx_info.version);

        if calls.len() == 1 {
            let call = calls.at(0);
            if *call.to == account_address {
                // This should only be called after an upgrade, never directly
                assert(*call.selector != EXECUTE_AFTER_UPGRADE_SELECTOR, 'argent/forbidden-call');
            }
        } else {
            // Make sure no call is to the account. We don't have any good reason to perform many calls to the account in the same transactions
            // and this restriction will reduce the attack surface
            assert_no_self_call(calls, account_address);
        }

        let valid = is_valid_span_signature(self, execution_hash, signature);
        assert(valid, 'argent/invalid-signature');
    }

    fn is_valid_span_signature(
        self: @ContractState, hash: felt252, signature: Span<felt252>
    ) -> bool {
        let threshold = self.get_threshold();
        assert(threshold != 0, 'argent/uninitialized');

        let mut signer_signatures = deserialize_array_signer_signature(signature)
            .expect('argent/invalid-signature-length');
        assert(signer_signatures.len() == threshold, 'argent/invalid-signature-length');

        let mut last_signer: felt252 = 0;
        loop {
            match signer_signatures.pop_front() {
                Option::Some(signer_sig_ref) => {
                    let signer_sig = *signer_sig_ref;
                    let last_signer_uint: u256 = last_signer.into();
                    let signer_uint: u256 = signer_sig.signer.into();
                    assert(signer_uint > last_signer_uint, 'argent/signatures-not-sorted');
                    let is_valid = is_valid_signer_signature_rename(
                        self,
                        hash,
                        signer: signer_sig.signer,
                        signature_r: signer_sig.signature_r,
                        signature_s: signer_sig.signature_s,
                    );
                    if !is_valid {
                        break false;
                    }
                    last_signer = signer_sig.signer;
                },
                Option::None(_) => {
                    break true;
                }
            };
        }
    }

    fn assert_valid_threshold_and_signers_count(threshold: usize, signers_len: usize) {
        assert(threshold != 0, 'argent/invalid-threshold');
        assert(signers_len != 0, 'argent/invalid-signers-len');
        assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        assert(threshold <= signers_len, 'argent/bad-threshold');
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                    Multisig Storage                                        //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[generate_trait]
    impl MultisigStorageImpl of MultisigStorage {
        ////////////////////////////////////////////////////////////////////////////////////////////////
        //                                          Internal                                          //
        ////////////////////////////////////////////////////////////////////////////////////////////////

        // Constant computation cost if `signer` is in fact in the list AND it's not the last one.
        // Otherwise cost increases with the list size
        fn is_signer(self: @ContractState, signer: felt252) -> bool {
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
        fn is_signer_using_last(
            self: @ContractState, signer: felt252, last_signer: felt252
        ) -> bool {
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

        fn add_signers(
            ref self: ContractState, mut signers_to_add: Span<felt252>, last_signer: felt252
        ) {
            match signers_to_add.pop_front() {
                Option::Some(signer_ref) => {
                    let signer = *signer_ref;
                    assert(signer != 0, 'argent/invalid-zero-signer');

                    let current_signer_status = self.is_signer_using_last(signer, last_signer);
                    assert(!current_signer_status, 'argent/already-a-signer');

                    // Signers are added at the end of the list
                    self.signer_list.write(last_signer, signer);

                    self.add_signers(signers_to_add, last_signer: signer);
                },
                Option::None(()) => (),
            }
        }

        fn remove_signers(
            ref self: ContractState, mut signers_to_remove: Span<felt252>, last_signer: felt252
        ) {
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
                        self.remove_signers(signers_to_remove, last_signer: previous_signer);
                    } else {
                        // Removing an item in the middle
                        self.signer_list.write(signer, 0);
                        self.remove_signers(signers_to_remove, last_signer);
                    }
                },
                Option::None(()) => (),
            }
        }

        fn replace_signer(
            ref self: ContractState,
            signer_to_remove: felt252,
            signer_to_add: felt252,
            last_signer: felt252
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

        fn get_signers(self: @ContractState) -> Array<felt252> {
            let mut current_signer = self.signer_list.read(0);
            let mut signers = ArrayTrait::new();
            loop {
                if current_signer == 0 {
                    // Can't break signers atm because "variable was previously moved"
                    break ();
                }
                signers.append(current_signer);
                current_signer = self.signer_list.read(current_signer);
            };
            signers
        }

        fn get_threshold(self: @ContractState) -> usize {
            self.threshold.read()
        }

        fn set_threshold(ref self: ContractState, threshold: usize) {
            self.threshold.write(threshold);
        }

        fn get_outside_nonce(self: @ContractState, nonce: felt252) -> bool {
            self.outside_nonces.read(nonce)
        }

        fn set_outside_nonce(ref self: ContractState, nonce: felt252, used: bool) {
            self.outside_nonces.write(nonce, used)
        }
    }
}
