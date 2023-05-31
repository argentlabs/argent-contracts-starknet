#[account_contract]
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

    use lib::{
        assert_only_self, assert_no_self_call, assert_correct_tx_version, assert_caller_is_null,
        execute_multicall, Call, Version, IErc165LibraryDispatcher, IErc165DispatcherTrait,
        SpanSerde, OutsideExecution, hash_outside_execution_message, ERC165_IERC165_INTERFACE_ID,
        ERC165_ACCOUNT_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID_OLD_1,
        ERC165_ACCOUNT_INTERFACE_ID_OLD_2, ERC1271_VALIDATED
    };
    use multisig::{
        IUpgradeTargetLibraryDispatcher, IUpgradeTargetDispatcherTrait,
        deserialize_array_signer_signature, MultisigStorage, SignerSignature
    };

    const EXECUTE_AFTER_UPGRADE_SELECTOR: felt252 =
        738349667340360233096752603318170676063569407717437256101137432051386874767; // starknet_keccak('execute_after_upgrade')

    const NAME: felt252 = 'ArgentMultisig';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 1;
    const VERSION_PATCH: u8 = 1;
    const VERSION_COMPAT: felt252 = '0.1.0';
    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Events                                           //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the multisig configuration changes
    /// @param new_threshold New threshold
    /// @param new_signers_count The number of signers after the update
    /// @param added_signers Signers added in this update
    /// @param removed_signers Signers removed by this update
    #[event]
    fn ConfigurationUpdated(
        new_threshold: usize,
        new_signers_count: usize,
        added_signers: Array<felt252>,
        removed_signers: Array<felt252>
    ) {}

    /// @notice Emitted when the account executes a transaction
    /// @param hash The transaction hash
    /// @param response The data returned by the methods called
    #[event]
    fn TransactionExecuted(hash: felt252, response: Span<Span<felt252>>) {}

    /// @notice Emitted when the implementation of the account changes
    /// @param new_implementation The new implementation
    #[event]
    fn AccountUpgraded(new_implementation: ClassHash) {}

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                     Constructor                                            //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[constructor]
    fn constructor(threshold: usize, signers: Array<felt252>) {
        let signers_len = signers.len();
        assert_valid_threshold_and_signers_count(threshold, signers_len);

        MultisigStorage::add_signers(signers.span(), last_signer: 0);
        MultisigStorage::set_threshold(threshold);

        ConfigurationUpdated(
            new_threshold: threshold,
            new_signers_count: signers_len,
            added_signers: signers,
            removed_signers: ArrayTrait::new()
        );
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                     External functions                                     //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[external]
    fn __validate__(calls: Array<Call>) -> felt252 {
        assert_caller_is_null();
        let tx_info = get_tx_info().unbox();
        assert_valid_calls_and_signature(calls.span(), tx_info.transaction_hash, tx_info.signature);
        VALIDATED
    }

    #[external]
    fn __execute__(calls: Array<Call>) -> Array<Span<felt252>> {
        assert_caller_is_null();
        let tx_info = starknet::get_tx_info().unbox();
        assert_correct_tx_version(tx_info.version);

        let retdata = execute_multicall(calls.span());
        TransactionExecuted(tx_info.transaction_hash, retdata.span());
        retdata
    }

    #[external]
    fn __validate_declare__(class_hash: felt252) -> felt252 {
        panic_with_felt252('argent/declare-not-available') // Not implemented yet
    }

    // Self deployment meaning that the multisig pays for it's own deployment fee.
    // In this scenario the multisig only requires the signature from one of the owners.
    // This allows for better UX. UI must make clear that the funds are not safe from a bad signer until the deployment happens.
    /// @dev Validates signature for self deployment.
    /// @dev If signers can't be trusted, it's recommended to start with a 1:1 multisig and add other signers late
    #[external]
    fn __validate_deploy__(
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<felt252>
    ) -> felt252 {
        let tx_info = starknet::get_tx_info().unbox();
        assert_correct_tx_version(tx_info.version);

        let parsed_signatures = deserialize_array_signer_signature(tx_info.signature)
            .expect('argent/invalid-signature-length');
        assert(parsed_signatures.len() == 1, 'argent/invalid-signature-length');

        let signer_sig = *parsed_signatures[0];
        let valid_signer_signature = is_valid_signer_signature(
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
    #[external]
    fn change_threshold(new_threshold: usize) {
        assert_only_self();

        let signers_len = MultisigStorage::get_signers_len();

        assert_valid_threshold_and_signers_count(new_threshold, signers_len);
        MultisigStorage::set_threshold(new_threshold);

        ConfigurationUpdated(
            new_threshold: new_threshold,
            new_signers_count: signers_len,
            added_signers: ArrayTrait::new(),
            removed_signers: ArrayTrait::new()
        );
    }

    /// @dev Adds new signers to the account, additionally sets a new threshold
    /// @param new_threshold New threshold
    /// @param signers_to_add An array with all the signers to add
    /// @dev will revert when trying to add a user already in the list
    #[external]
    fn add_signers(new_threshold: usize, signers_to_add: Array<felt252>) {
        assert_only_self();
        let (signers_len, last_signer) = MultisigStorage::load();

        let new_signers_len = signers_len + signers_to_add.len();
        assert_valid_threshold_and_signers_count(new_threshold, new_signers_len);

        MultisigStorage::add_signers(signers_to_add.span(), last_signer);
        MultisigStorage::set_threshold(new_threshold);

        ConfigurationUpdated(
            new_threshold: new_threshold,
            new_signers_count: new_signers_len,
            added_signers: signers_to_add,
            removed_signers: ArrayTrait::new()
        );
    }

    /// @dev Removes account signers, additionally sets a new threshold
    /// @param new_threshold New threshold
    /// @param signers_to_remove Should contain only current signers, otherwise it will revert
    #[external]
    fn remove_signers(new_threshold: usize, signers_to_remove: Array<felt252>) {
        assert_only_self();
        let (signers_len, last_signer) = MultisigStorage::load();

        let new_signers_len = signers_len - signers_to_remove.len();
        assert_valid_threshold_and_signers_count(new_threshold, new_signers_len);

        MultisigStorage::remove_signers(signers_to_remove.span(), last_signer);
        MultisigStorage::set_threshold(new_threshold);

        ConfigurationUpdated(
            new_threshold: new_threshold,
            new_signers_count: new_signers_len,
            added_signers: ArrayTrait::new(),
            removed_signers: signers_to_remove
        );
    }

    /// @dev Replace one signer with a different one
    /// @param signer_to_remove Signer to remove
    /// @param signer_to_add Signer to add
    #[external]
    fn replace_signer(signer_to_remove: felt252, signer_to_add: felt252) {
        assert_only_self();
        let (signers_len, last_signer) = MultisigStorage::load();

        MultisigStorage::replace_signer(signer_to_remove, signer_to_add, last_signer);

        let mut added_signers = ArrayTrait::new();
        added_signers.append(signer_to_add);

        let mut removed_signer = ArrayTrait::new();
        removed_signer.append(signer_to_remove);

        ConfigurationUpdated(
            new_threshold: MultisigStorage::get_threshold(),
            new_signers_count: signers_len,
            added_signers: added_signers,
            removed_signers: removed_signer
        );
    }

    /// @dev Can be called by the account to upgrade the implementation
    /// @param calldata Will be passed to the new implementation `execute_after_upgrade` method
    /// @param implementation class hash of the new implementation 
    /// @return retdata The data returned by `execute_after_upgrade`
    #[external]
    fn upgrade(implementation: ClassHash, calldata: Array<felt252>) -> Array<felt252> {
        assert_only_self();

        let supports_interface = IErc165LibraryDispatcher {
            class_hash: implementation
        }.supports_interface(ERC165_ACCOUNT_INTERFACE_ID);
        assert(supports_interface, 'argent/invalid-implementation');

        replace_class_syscall(implementation).unwrap_syscall();
        AccountUpgraded(implementation);

        IUpgradeTargetLibraryDispatcher {
            class_hash: implementation
        }.execute_after_upgrade(calldata)
    }

    /// see `IUpgradeTarget`
    #[external]
    fn execute_after_upgrade(data: Array<felt252>) -> Array<felt252> {
        assert_only_self();

        // Check basic invariants
        assert_valid_threshold_and_signers_count(
            MultisigStorage::get_threshold(), MultisigStorage::get_signers_len()
        );

        assert(data.len() == 0, 'argent/unexpected-data');
        ArrayTrait::new()
    }

    /// @notice This method allows anyone to submit a transaction on behalf of the account as long as they have the relevant signatures
    /// @param outside_execution The parameters of the transaction to execute
    /// @param signature A valid signature on the Eip712 message encoding of `outside_execution`
    /// @notice This method allows reentrancy. A call to `__execute__` or `execute_from_outside` can trigger another nested transaction to `execute_from_outside`.
    #[external]
    fn execute_from_outside(
        outside_execution: OutsideExecution, signature: Array<felt252>
    ) -> Array<Span<felt252>> {
        // Checks
        if outside_execution.caller.into() != 'ANY_CALLER' {
            assert(get_caller_address() == outside_execution.caller, 'argent/invalid-caller');
        }

        let block_timestamp = get_block_timestamp();
        assert(
            outside_execution.execute_after < block_timestamp
                & block_timestamp < outside_execution.execute_before,
            'argent/invalid-timestamp'
        );
        let nonce = outside_execution.nonce;
        assert(!MultisigStorage::get_outside_nonce(nonce), 'argent/duplicated-outside-nonce');

        let outside_tx_hash = hash_outside_execution_message(@outside_execution);

        let calls = outside_execution.calls.span();

        assert_valid_calls_and_signature(calls, outside_tx_hash, signature.span());

        // Effects
        MultisigStorage::set_outside_nonce(nonce, true);

        // Interactions
        let retdata = execute_multicall(calls);
        TransactionExecuted(outside_tx_hash, retdata.span());
        retdata
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                       View functions                                       //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[view]
    fn get_name() -> felt252 {
        NAME
    }

    /// Deprecated method for compatibility reasons
    #[view]
    fn getName() -> felt252 {
        get_name()
    }

    /// Semantic version of this contract
    #[view]
    fn get_version() -> Version {
        Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
    }

    /// Deprecated method for compatibility reasons
    #[view]
    fn getVersion() -> felt252 {
        VERSION_COMPAT
    }

    /// @dev Returns the threshold, the number of signers required to control this account
    #[view]
    fn get_threshold() -> usize {
        MultisigStorage::get_threshold()
    }

    #[view]
    fn get_signers() -> Array<felt252> {
        MultisigStorage::get_signers()
    }

    #[view]
    fn is_signer(signer: felt252) -> bool {
        MultisigStorage::is_signer(signer)
    }

    // ERC165
    #[view]
    fn supports_interface(interface_id: felt252) -> bool {
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
    fn supportsInterface(interface_id: felt252) -> felt252 {
        if supports_interface(interface_id) {
            1
        } else {
            0
        }
    }

    /// Asserts that the given signature is a valid signature from one of the multisig owners
    /// Deprecated method for compatibility reasons
    #[view]
    fn assert_valid_signer_signature(
        hash: felt252, signer: felt252, signature_r: felt252, signature_s: felt252
    ) {
        let is_valid = is_valid_signer_signature(hash, signer, signature_r, signature_s);
        assert(is_valid, 'argent/invalid-signature');
    }

    #[view]
    /// Checks if a given signature is a valid signature from one of the multisig owners
    fn is_valid_signer_signature(
        hash: felt252, signer: felt252, signature_r: felt252, signature_s: felt252
    ) -> bool {
        let is_signer = MultisigStorage::is_signer(signer);
        assert(is_signer, 'argent/not-a-signer');
        check_ecdsa_signature(hash, signer, signature_r, signature_s)
    }

    // ERC1271
    #[view]
    fn is_valid_signature(hash: felt252, signatures: Array<felt252>) -> felt252 {
        if is_valid_span_signature(hash, signatures.span()) {
            ERC1271_VALIDATED
        } else {
            0
        }
    }

    #[view]
    /// Deprecated method for compatibility reasons
    fn isValidSignature(hash: felt252, signatures: Array<felt252>) -> felt252 {
        is_valid_signature(hash, signatures)
    }

    /// Get the message hash for some `OutsideExecution` following Eip712. Can be used to know what needs to be signed
    #[view]
    fn get_outside_execution_message_hash(outside_execution: OutsideExecution) -> felt252 {
        return hash_outside_execution_message(@outside_execution);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                   Internal Functions                                       //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    fn assert_valid_calls_and_signature(
        calls: Span<Call>, execution_hash: felt252, signature: Span<felt252>
    ) {
        let account_address = get_contract_address();
        let tx_info = get_tx_info().unbox();
        assert_correct_tx_version(tx_info.version);

        if calls.len() == 1 {
            let call = calls[0];
            if *call.to == account_address {
                // This should only be called after an upgrade, never directly
                assert(*call.selector != EXECUTE_AFTER_UPGRADE_SELECTOR, 'argent/forbidden-call');
            }
        } else {
            // Make sure no call is to the account. We don't have any good reason to perform many calls to the account in the same transactions
            // and this restriction will reduce the attack surface
            assert_no_self_call(calls, account_address);
        }

        let valid = is_valid_span_signature(execution_hash, signature);
        assert(valid, 'argent/invalid-signature');
    }

    fn is_valid_span_signature(hash: felt252, signature: Span<felt252>) -> bool {
        let threshold = MultisigStorage::get_threshold();
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
                    let is_valid = is_valid_signer_signature(
                        hash: hash,
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
}
