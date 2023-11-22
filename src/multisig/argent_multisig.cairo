#[starknet::contract]
mod ArgentMultisig {
    use argent::common::{
        account::{
            IAccount, ERC165_ACCOUNT_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID_OLD_1, ERC165_ACCOUNT_INTERFACE_ID_OLD_2
        },
        asserts::{assert_correct_tx_version, assert_no_self_call, assert_caller_is_null, assert_only_self,},
        erc165::{
            IErc165, IErc165LibraryDispatcher, IErc165DispatcherTrait, ERC165_IERC165_INTERFACE_ID,
            ERC165_IERC165_INTERFACE_ID_OLD,
        },
        execute_from_outside::execute_from_outside_component, calls::execute_multicall, version::Version,
        outside_execution::{IOutsideExecutionCallback, ERC165_OUTSIDE_EXECUTION_INTERFACE_ID},
        upgrade::{IUpgradeable, IUpgradeableLibraryDispatcher, IUpgradeableDispatcherTrait}
    };
    use argent::multisig::interface::{IArgentMultisig, IDeprecatedArgentMultisig};
    use argent::multisig::signer_signature::{deserialize_array_signer_signature};
    use ecdsa::check_ecdsa_signature;
    use starknet::{
        get_contract_address, VALIDATED, syscalls::replace_class_syscall, ClassHash, get_caller_address, get_tx_info,
        account::Call
    };

    const NAME: felt252 = 'ArgentMultisig';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 1;
    const VERSION_PATCH: u8 = 0;
    const VERSION_COMPAT: felt252 = '0.1.0';
    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    component!(path: execute_from_outside_component, storage: execute_from_outside, event: ExecuteFromOutsideEvents);
    #[abi(embed_v0)]
    impl List = execute_from_outside_component::OutsideExecutionImpl<ContractState>;

    impl OutsideExecutionCallbackImpl of IOutsideExecutionCallback<ContractState> {
        #[inline(always)]
        fn assert_valid_calls_and_signature_callback(
            ref self: ContractState, calls: Span<Call>, execution_hash: felt252, signature: Span<felt252>,
        ) {
            self.assert_valid_calls_and_signature(calls, execution_hash, signature);
        }

        #[inline(always)]
        fn emit_transaction_executed(ref self: ContractState, hash: felt252, response: Span<Span<felt252>>) {
            self.emit(TransactionExecuted { hash, response });
        }
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        execute_from_outside: execute_from_outside_component::Storage,
        signer_list: LegacyMap<felt252, felt252>,
        threshold: usize,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ExecuteFromOutsideEvents: execute_from_outside_component::Event,
        ThresholdUpdated: ThresholdUpdated,
        TransactionExecuted: TransactionExecuted,
        AccountUpgraded: AccountUpgraded,
        OwnerAdded: OwnerAdded,
        OwnerRemoved: OwnerRemoved
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
            }
        }
    }

    #[external(v0)]
    impl Account of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            assert_caller_is_null();
            let tx_info = get_tx_info().unbox();
            self.assert_valid_calls_and_signature(calls.span(), tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert_caller_is_null();
            let tx_info = get_tx_info().unbox();
            assert_correct_tx_version(tx_info.version);

            let retdata = execute_multicall(calls.span());
            self.emit(TransactionExecuted { hash: tx_info.transaction_hash, response: retdata.span() });
            retdata
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            if self.is_valid_span_signature(hash, signature.span()) {
                VALIDATED
            } else {
                0
            }
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

            let parsed_signatures = deserialize_array_signer_signature(tx_info.signature)
                .expect('argent/invalid-signature-length');
            assert(parsed_signatures.len() == 1, 'argent/invalid-signature-length');

            let signer_sig = *parsed_signatures.at(0);
            let valid_signer_signature = self
                .is_valid_signer_signature_inner(
                    tx_info.transaction_hash, signer_sig.signer, signer_sig.signature_r, signer_sig.signature_s
                );
            assert(valid_signer_signature, 'argent/invalid-signature');
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
                }
            }
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
                }
            }
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

        fn is_valid_signer_signature(
            self: @ContractState, hash: felt252, signer: felt252, signature_r: felt252, signature_s: felt252
        ) -> bool {
            self.is_valid_signer_signature_inner(hash, signer, signature_r, signature_s)
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
    impl OldArgentMultisigImpl<
        impl ArgentMultisig: IArgentMultisig<ContractState>,
        impl Erc165: IErc165<ContractState>,
        impl Account: IAccount<ContractState>,
    > of IDeprecatedArgentMultisig<ContractState> {
        fn getVersion(self: @ContractState) -> felt252 {
            VERSION_COMPAT
        }

        fn getName(self: @ContractState) -> felt252 {
            ArgentMultisig::get_name(self)
        }

        fn supportsInterface(self: @ContractState, interface_id: felt252) -> felt252 {
            if Erc165::supports_interface(self, interface_id) {
                1
            } else {
                0
            }
        }

        fn isValidSignature(self: @ContractState, hash: felt252, signatures: Array<felt252>) -> felt252 {
            assert(Account::is_valid_signature(self, hash, signatures) == VALIDATED, 'argent/invalid-signature');
            1
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
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
                    assert(*call.selector != selector!("execute_after_upgrade"), 'argent/forbidden-call');
                }
            } else {
                // Make sure no call is to the account. We don't have any good reason to perform many calls to the account in the same transactions
                // and this restriction will reduce the attack surface
                assert_no_self_call(calls, account_address);
            }

            let valid = self.is_valid_span_signature(execution_hash, signature);
            assert(valid, 'argent/invalid-signature');
        }

        fn is_valid_span_signature(self: @ContractState, hash: felt252, signature: Span<felt252>) -> bool {
            let threshold = self.threshold.read();
            assert(threshold != 0, 'argent/uninitialized');

            let mut signer_signatures = deserialize_array_signer_signature(signature)
                .expect('argent/invalid-signature-length');
            assert(signer_signatures.len() == threshold, 'argent/invalid-signature-length');

            let mut last_signer: u256 = 0;
            loop {
                match signer_signatures.pop_front() {
                    Option::Some(signer_sig_ref) => {
                        let signer_sig = *signer_sig_ref;
                        let signer_uint: u256 = signer_sig.signer.into();
                        assert(signer_uint > last_signer, 'argent/signatures-not-sorted');
                        let is_valid = self
                            .is_valid_signer_signature(
                                hash,
                                signer: signer_sig.signer,
                                signature_r: signer_sig.signature_r,
                                signature_s: signer_sig.signature_s,
                            );
                        if !is_valid {
                            break false;
                        }
                        last_signer = signer_uint;
                    },
                    Option::None => { break true; }
                }
            }
        }

        fn is_valid_signer_signature_inner(
            self: @ContractState, hash: felt252, signer: felt252, signature_r: felt252, signature_s: felt252
        ) -> bool {
            let is_signer = self.is_signer_inner(signer);
            assert(is_signer, 'argent/not-a-signer');
            check_ecdsa_signature(hash, signer, signature_r, signature_s)
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
}
