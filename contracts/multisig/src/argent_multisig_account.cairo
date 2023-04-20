#[account_contract]
mod ArgentMultisigAccount {
    use array::ArrayTrait;
    use array::SpanTrait;
    use box::BoxTrait;
    use ecdsa::check_ecdsa_signature;
    use option::OptionTrait;
    use traits::Into;
    use zeroable::Zeroable;

    use starknet::get_contract_address;
    use starknet::ContractAddressIntoFelt252;
    use starknet::VALIDATED;
    use starknet::syscalls::replace_class_syscall;
    use starknet::ClassHash;
    use starknet::class_hash_const;

    use lib::assert_only_self;
    use lib::assert_no_self_call;
    use lib::assert_correct_tx_version;
    use lib::assert_non_reentrant;
    use lib::check_enough_gas;
    use lib::execute_multicall;
    use lib::Call;
    use lib::Version;
    use lib::IErc165LibraryDispatcher;
    use lib::IErc165DispatcherTrait;
    use multisig::IUpgradeTargetLibraryDispatcher;
    use multisig::IUpgradeTargetDispatcherTrait;
    use multisig::deserialize_array_signer_signature;
    use multisig::spans;
    use multisig::MultisigStorage;
    use multisig::SignerSignature;
    use multisig::SignerSignatureSize;

    const ERC165_IERC165_INTERFACE_ID: felt252 = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt252 = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt252 = 0x3943f10f;


    const EXECUTE_AFTER_UPGRADE_SELECTOR: felt252 =
        738349667340360233096752603318170676063569407717437256101137432051386874767; // execute_after_upgrade

    const NAME: felt252 = 'ArgentMultisig';

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                           Events                                           //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[event]
    fn ConfigurationUpdated(
        new_threshold: usize,
        new_signers_count: usize,
        added_signers: Array<felt252>,
        removed_signers: Array<felt252>
    ) {}

    #[event]
    fn TransactionExecuted(hash: felt252, response: Array<felt252>) {}

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
        let account_address = get_contract_address();

        if calls.len() == 1 {
            let call = calls[0];
            if (*call.to).into() == account_address.into() {
                // This should only be called after an upgrade, never directly
                assert(*call.selector != EXECUTE_AFTER_UPGRADE_SELECTOR, 'argent/forbidden-call');
            }
        } else {
            // Make sure no call is to the account. We don't have any good reason to perform many calls to the account in the same transactions
            // and this restriction will reduce the attack surface
            assert_no_self_call(calls.span(), account_address);
        }

        assert_is_valid_tx_signature();

        VALIDATED
    }

    #[external]
    #[raw_output]
    fn __execute__(calls: Array<Call>) -> Span::<felt252> {
        let tx_info = starknet::get_tx_info().unbox();
        assert_correct_tx_version(tx_info.version);
        assert_non_reentrant();

        let retdata = execute_multicall(calls);
        let retdata_span = retdata.span();
        TransactionExecuted(tx_info.transaction_hash, retdata);
        retdata_span
    }

    #[external]
    fn __validate_declare__(class_hash: felt252) -> felt252 {
        assert_is_valid_tx_signature();
        VALIDATED
    }

    // Self deployment meaning that the multisig pays for it's own deployment fee.
    // In this scenario the multisig only requires the signature from one of the owners.
    // This allows for better UX. UI must make clear that the funds are not safe from a bad signer until the deployment happens.
    /// @dev Validates signature for self deployment.
    /// @dev If signers can't be trusted, it's recommended to start with a 1:1 multisig and add other signers late
    #[raw_input]
    #[external]
    fn __validate_deploy__(
        class_hash: felt252,
        contract_address_salt: felt252,
        threshold: usize,
        signers: Array<felt252>
    ) -> felt252 {
        let tx_info = starknet::get_tx_info().unbox();
        let signature_array = spans::span_to_array(tx_info.signature);

        assert(signature_array.len() == SignerSignatureSize, 'argent/invalid-signature-length');

        let mut signer_signatures_out = ArrayTrait::<SignerSignature>::new();
        let parsed_signatures = deserialize_array_signer_signature(
            serialized: signature_array,
            current_output: signer_signatures_out,
            remaining: 1 // only one signature is provided as asserted above
        ).unwrap();

        let valid = is_valid_signatures_array(tx_info.transaction_hash, parsed_signatures.span());
        assert(valid, 'argent/invalid-signature');
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
    fn upgrade(implementation: ClassHash, calldata: Array<felt252>) -> Array::<felt252> {
        assert_only_self();

        let supports_interface = IErc165LibraryDispatcher {
            class_hash: implementation
        }.supports_interface(ERC165_ACCOUNT_INTERFACE_ID);
        assert(supports_interface, 'argent/invalid-implementation');

        let old_version = get_version();
        replace_class_syscall(implementation).unwrap_syscall();
        let return_data = IUpgradeTargetLibraryDispatcher {
            class_hash: implementation
        }.execute_after_upgrade(old_version, calldata);

        AccountUpgraded(implementation);
        return_data
    }


    /// see `IUpgradeTarget`
    #[external]
    fn execute_after_upgrade(previous_version: Version, data: Array<felt252>) -> Array::<felt252> {
        assert_only_self();
        assert(data.len() == 0, 'argent/unexpected-data');

        let implementation = MultisigStorage::get_implementation();
        if implementation != class_hash_const::<0>() {
            replace_class_syscall(implementation).unwrap_syscall();
            MultisigStorage::set_implementation(class_hash_const::<0>());
        }
        ArrayTrait::new()
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                       View functions                                       //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    #[view]
    fn get_name() -> felt252 {
        NAME
    }

    #[view]
    fn get_version() -> Version {
        Version { major: 0, minor: 1, patch: 0 }
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
        } else if interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID {
            true
        } else {
            false
        }
    }

    /// @dev Assert that the given signature is a valid signature from one of the multisig owners
    #[view]
    fn assert_valid_signer_signature(
        hash: felt252, signer: felt252, signature_r: felt252, signature_s: felt252
    ) {
        let is_valid = is_valid_signer_signature(hash, signer, signature_r, signature_s);
        assert(is_valid, 'argent/invalid-signature');
    }

    #[view]
    fn is_valid_signer_signature(
        hash: felt252, signer: felt252, signature_r: felt252, signature_s: felt252
    ) -> bool {
        let is_signer = MultisigStorage::is_signer(signer);
        assert(is_signer, 'argent/not-a-signer');
        check_ecdsa_signature(hash, signer, signature_r, signature_s)
    }

    #[view]
    fn is_valid_signature(hash: felt252, signatures: Array<felt252>) -> bool {
        let threshold = MultisigStorage::get_threshold();
        assert(threshold != 0, 'argent/uninitialized');
        assert(
            signatures.len() == threshold * SignerSignatureSize, 'argent/invalid-signature-length'
        );
        let mut mut_signatures = signatures;
        let mut signer_signatures_out = ArrayTrait::<SignerSignature>::new();
        let parsed_signatures = deserialize_array_signer_signature(
            serialized: mut_signatures, current_output: signer_signatures_out, remaining: threshold
        ).unwrap();
        is_valid_signatures_array(hash, parsed_signatures.span())
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                   Internal Functions                                       //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    fn assert_is_valid_tx_signature() {
        let tx_info = starknet::get_tx_info().unbox();

        // TODO converting to array is probably avoidable
        let signature_array = spans::span_to_array(tx_info.signature);

        let valid = is_valid_signature(tx_info.transaction_hash, signature_array);
        assert(valid, 'argent/invalid-signature');
    }

    /// Validates tha all the signatures are valid and different.
    /// the signatures needs to be sorted by signer
    /// ATTENTION: an empty array is considered valid
    fn is_valid_signatures_array(hash: felt252, signatures: Span<SignerSignature>) -> bool {
        is_valid_signatures_array_helper(hash, signatures, last_signer: 0)
    }

    fn is_valid_signatures_array_helper(
        hash: felt252, mut signatures: Span<SignerSignature>, last_signer: felt252
    ) -> bool {
        check_enough_gas();

        match signatures.pop_front() {
            Option::Some(signer_sig_ref) => {
                let signer_sig = *signer_sig_ref;
                assert(
                    signer_sig.signer.into() > last_signer.into(), 'argent/signatures-not-sorted'
                );
                let valid_signer_signature = is_valid_signer_signature(
                    hash, signer_sig.signer, signer_sig.signature_r, signer_sig.signature_s
                );
                if !valid_signer_signature {
                    return false;
                }
                is_valid_signatures_array_helper(hash, signatures, signer_sig.signer)
            },
            Option::None(_) => true
        }
    }

    fn assert_valid_threshold_and_signers_count(threshold: usize, signers_len: usize) {
        assert(threshold != 0, 'argent/invalid-threshold');
        assert(signers_len != 0, 'argent/invalid-signers-len');
        assert(threshold <= signers_len, 'argent/bad-threshold');
    }
}