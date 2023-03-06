#[account_contract]
mod ArgentMultisigAccount {
    use array::ArrayTrait;
    use array::SpanTrait;
    use traits::Into;
    use traits::TryInto;
    use zeroable::Zeroable;
    use option::OptionTrait;
    use ecdsa::check_ecdsa_signature;
    use gas::get_gas_all;
    use starknet::get_contract_address;
    use contracts::asserts;
    use contracts::signer_signature::SignerSignature;
    use contracts::signer_signature::deserialize_array_signer_signature;
    use contracts::signer_signature::SignerSignatureSize;
    use contracts::signer_signature::SignerSignatureArrayCopy;
    use contracts::signer_signature::SignerSignatureArrayDrop;
    use contracts::calls::Call;
    use contracts::spans;

    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    const EXECUTE_AFTER_UPGRADE_SELECTOR: felt =
        738349667340360233096752603318170676063569407717437256101137432051386874767;


    const NAME: felt = 'ArgentMultisig';
    const VERSION: felt = '0.1.0-alpha.1';

    struct Storage {
        threshold: u32,
        signer_list: LegacyMap<felt, felt>,
    }

    #[event]
    fn configuration_updated(
        new_threshold: u32,
        new_signers_count: u32,
        added_signers: Array<felt>,
        removed_signers: Array<felt>
    ) {}

    /////////////////////////////////////////////////////////
    // VIEW FUNCTIONS
    /////////////////////////////////////////////////////////

    #[view]
    fn get_name() -> felt {
        NAME
    }

    #[view]
    fn get_version() -> felt {
        VERSION
    }

    #[view]
    fn get_threshold() -> u32 {
        threshold::read()
    }

    #[view]
    fn get_signers() -> Array<felt> {
        signers_storage::get_signers()
    }

    #[view]
    fn is_signer(signer: felt) -> bool {
        signers_storage::is_signer(signer)
    }

    // ERC165
    #[view]
    fn supports_interface(interface_id: felt) -> bool {
        interface_id == ERC165_IERC165_INTERFACE_ID | interface_id == ERC165_ACCOUNT_INTERFACE_ID | interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID
    }

    #[view]
    fn assert_valid_signer_signature(
        hash: felt, signer: felt, signature_r: felt, signature_s: felt
    ) {
        let is_valid = is_valid_signer_signature(hash, signer, signature_r, signature_s);
        assert(is_valid, 'argent/invalid-signature');
    }

    #[view]
    fn is_valid_signer_signature(
        hash: felt, signer: felt, signature_r: felt, signature_s: felt
    ) -> bool {
        let is_signer = signers_storage::is_signer(signer);
        assert(is_signer, 'argent/not-a-signer');
        check_ecdsa_signature(hash, signer, signature_r, signature_s)
    }

    #[view]
    fn is_valid_signature(hash: felt, signatures: Array<felt>) -> bool {
        let threshold = threshold::read();
        assert(threshold != 0_usize, 'argent/not-initialized');
        assert(
            signatures.len() == threshold * SignerSignatureSize, 'argent/invalid-signature-length'
        );
        let mut mut_signatures = signatures;
        let mut signer_signatures_out = ArrayTrait::<SignerSignature>::new();
        let parsed_signatures = deserialize_array_signer_signature(
            mut_signatures, signer_signatures_out, threshold
        ).unwrap();
        is_valid_signatures_array(hash, parsed_signatures.span())
    }

    /////////////////////////////////////////////////////////
    // EXTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////

    // TODO use the actual signature of the account interface
    // #[external] // ignored to avoid serde
    fn __validate__(ref calls: Array<Call>) {
        assert_initialized();

        let account_address = get_contract_address();

        if calls.len() == 1_usize {
            let call = calls.at(0_usize);
            if (*call.to).into() == account_address.into() {
                let selector = *call.selector;
                assert(selector != EXECUTE_AFTER_UPGRADE_SELECTOR, 'argent/forbidden-call');
            }
        } else {
            // make sure no call is to the account
            asserts::assert_no_self_call(@calls, account_address);
        }

        let tx_info = unbox(starknet::get_tx_info());

        // TODO converting to array is probably avoidable
        let signature_array = spans::span_to_array(tx_info.signature);

        let valid = is_valid_signature(tx_info.transaction_hash, signature_array);
        assert(valid, 'argent/invalid-signature');
    }

    // @dev Set the initial parameters for the multisig. It's mandatory to call this methods to secure the account.
    // It's recommended to call this method in the same transaction that deploys the account to make sure it's always initialized
    #[external]
    fn initialize(threshold: u32, signers: Array<felt>) {
        let current_threshold = threshold::read();
        assert(current_threshold == 0_u32, 'argent/already-initialized');

        let signers_len = signers.len();
        assert_valid_threshold_and_signers_count(threshold, signers_len);

        signers_storage::add_signers(signers.span(), 0);
        threshold::write(threshold);

        let mut removed_signers = ArrayTrait::new();

        configuration_updated(threshold, signers_len, signers, removed_signers);
    }

    #[external]
    fn change_threshold(new_threshold: u32) {
        asserts::assert_only_self();

        let signers_len = signers_storage::get_signers_len();

        assert_valid_threshold_and_signers_count(new_threshold, signers_len);
        threshold::write(new_threshold);

        let mut added_signers = ArrayTrait::new();
        let mut removed_signers = ArrayTrait::new();

        configuration_updated(new_threshold, signers_len, added_signers, removed_signers);
    }

    // @dev Adds new signers to the account, additionally sets a new threshold
    // @param new_threshold New threshold
    // @param signers_to_add Contains the new signers, it will revert if it contains any existing signer
    #[external]
    fn add_signers(new_threshold: u32, signers_to_add: Array<felt>) {
        asserts::assert_only_self();
        let (signers_len, last_signer) = signers_storage::load();

        let new_signers_len = signers_len + signers_to_add.len();

        assert_valid_threshold_and_signers_count(new_threshold, new_signers_len);

        signers_storage::add_signers(signers_to_add.span(), last_signer);
        threshold::write(new_threshold);

        let mut removed_signers = ArrayTrait::new();

        configuration_updated(new_threshold, new_signers_len, signers_to_add, removed_signers);
    }

    // @dev Removes account signers, additionally sets a new threshold
    // @param new_threshold New threshold
    // @param signers_to_remove Should contain only current signers, otherwise it will revert
    #[external]
    fn remove_signers(new_threshold: u32, signers_to_remove: Array<felt>) {
        asserts::assert_only_self();
        let (signers_len, last_signer) = signers_storage::load();

        let new_signers_len = signers_len - signers_to_remove.len();

        assert_valid_threshold_and_signers_count(new_threshold, new_signers_len);

        signers_storage::remove_signers(signers_to_remove.span(), last_signer);
        threshold::write(new_threshold);

        let mut added_signers = ArrayTrait::new();

        configuration_updated(new_threshold, new_signers_len, added_signers, signers_to_remove);
    }

    // @dev Replace one signer with a different one
    // @param signer_to_remove Signer to remove
    // @param signer_to_add Signer to add
    #[external]
    fn replace_signer(signer_to_remove: felt, signer_to_add: felt) {
        asserts::assert_only_self();
        let (signers_len, last_signer) = signers_storage::load();

        signers_storage::replace_signer(signer_to_remove, signer_to_add, last_signer);

        let mut added_signers = ArrayTrait::new();
        added_signers.append(signer_to_add);

        let mut removed_signer = ArrayTrait::new();
        removed_signer.append(signer_to_remove);

        configuration_updated(threshold::read(), signers_len, added_signers, removed_signer);
    }

    /////////////////////////////////////////////////////////
    // INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////

    fn is_valid_signatures_array(hash: felt, signatures: Span<SignerSignature>) -> bool {
        is_valid_signatures_array_helper(hash, signatures, 0)
    }

    fn is_valid_signatures_array_helper(
        hash: felt, mut signatures: Span<SignerSignature>, last_signer: felt
    ) -> bool {
        match get_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = array_new();
                array_append(ref err_data, 'Out of gas');
                panic(err_data)
            }
        }

        match signatures.pop_front() {
            Option::Some(i) => {
                let signer_sig = *i;
                assert(signer_sig.signer > last_signer, 'argent/signatures-not-sorted');
                let valid_signer_signature = is_valid_signer_signature(
                    hash, signer_sig.signer, signer_sig.signature_r, signer_sig.signature_s
                );
                if !valid_signer_signature {
                    return false;
                }
                return is_valid_signatures_array_helper(hash, signatures, signer_sig.signer);
            },
            Option::None(_) => {
                return true;
            }
        }
    }

    fn assert_valid_threshold_and_signers_count(threshold: u32, signers_len: u32) {
        assert(threshold != 0_u32, 'argent/invalid-threshold');
        assert(signers_len != 0_u32, 'argent/invalid-signers-len');
        assert(threshold <= signers_len, 'argent/bad-threshold');
    }

    fn assert_initialized() {
        let threshold = threshold::read();
        assert(threshold != 0_u32, 'argent/not-initialized');
    }


    // This module handles the storage of the multisig owners using a linked set
    // you can't store signer 0 and you can't store duplicates.
    // This allows to retrieve the list of owners easily.
    // In terms of storage this will use one storage slot per signer
    // Reading become a bit more expensive for some operations as it need to go through the full list for some operations
    mod signers_storage {
        use array::ArrayTrait;
        use array::SpanTrait;
        use gas::get_gas_all;


        // Constant computation cost if `signer` is in fact in the list AND it's not the last one.
        // Otherwise cost increases with the list size
        fn is_signer(signer: felt) -> bool {
            if (signer == 0) {
                return false;
            }
            let next_signer = super::signer_list::read(signer);
            if (next_signer != 0) {
                return true;
            }
            // check if its the latest
            let last_signer = find_last_signer();
            return last_signer == signer;
        }

        // Optimized version of `is_signer` with constant compute cost. To use when you know the last signer
        fn is_signer_using_last(signer: felt, last_signer: felt) -> bool {
            if (signer == 0) {
                return false;
            }

            let next_signer = super::signer_list::read(signer);
            if (next_signer != 0) {
                return true;
            }

            return last_signer == signer;
        }

        // Return the last signer or zero if no signers. Cost increases with the list size
        fn find_last_signer() -> felt {
            let first_signer = super::signer_list::read(0);
            find_last_signer_recursive(first_signer)
        }

        fn find_last_signer_recursive(from_signer: felt) -> felt {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                },
            }

            let next_signer = super::signer_list::read(from_signer);
            if (next_signer == 0) {
                return from_signer;
            }
            find_last_signer_recursive(next_signer)
        }

        // Returns the signer before `signer_after` or 0 if the signer is the first one. 
        // Reverts if `signer_after` is not found
        // Cost increases with the list size
        fn find_signer_before(signer_after: felt) -> felt {
            find_signer_before_recursive(signer_after, 0)
        }

        fn find_signer_before_recursive(signer_after: felt, from_signer: felt) -> felt {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                },
            }

            let next_signer = super::signer_list::read(from_signer);
            assert(next_signer != 0, 'argent/cant-find-signer-before');

            if (next_signer == signer_after) {
                return from_signer;
            }
            find_signer_before_recursive(signer_after, next_signer)
        }

        fn add_signers(mut signers_to_add: Span<felt>, last_signer: felt) {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                },
            }

            match signers_to_add.pop_front() {
                Option::Some(i) => {
                    let signer = *i;
                    assert(signer != 0, 'argent/invalid-zero-signer');

                    let current_signer_status = is_signer_using_last(signer, last_signer);
                    assert(!current_signer_status, 'argent/already-a-signer');

                    // Signers are added at the end of the list
                    super::signer_list::write(last_signer, signer);

                    add_signers(signers_to_add, signer);
                },
                Option::None(()) => (),
            }
        }

        fn remove_signers(mut signers_to_remove: Span<felt>, last_signer: felt) {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                },
            }

            match signers_to_remove.pop_front() {
                Option::Some(i) => {
                    let signer = *i;
                    let current_signer_status = is_signer_using_last(signer, last_signer);
                    assert(current_signer_status, 'argent/not-a-signer');

                    let previous_signer = find_signer_before(signer);
                    let next_signer = super::signer_list::read(signer);

                    super::signer_list::write(previous_signer, next_signer);

                    if (next_signer == 0) {
                        // Removing the last item
                        remove_signers(signers_to_remove, previous_signer);
                    } else {
                        // Removing an item in the middle
                        super::signer_list::write(signer, 0);
                        remove_signers(signers_to_remove, last_signer);
                    }
                },
                Option::None(()) => (),
            }
        }

        fn replace_signer(signer_to_remove: felt, signer_to_add: felt, last_signer: felt) {
            assert(signer_to_add != 0, 'argent/invalid-zero-signer');

            let signer_to_add_status = is_signer_using_last(signer_to_add, last_signer);
            assert(!signer_to_add_status, 'argent/already-a-signer');

            let signer_to_remove_status = is_signer_using_last(signer_to_remove, last_signer);
            assert(signer_to_remove_status, 'argent/not-a-signer');

            // removed signer will point to 0
            // previous signer will point to the new one
            // new signer will point to the next one
            let previous_signer = find_signer_before(signer_to_remove);
            let next_signer = super::signer_list::read(signer_to_remove);

            super::signer_list::write(signer_to_remove, 0);
            super::signer_list::write(previous_signer, signer_to_add);
            super::signer_list::write(signer_to_add, next_signer);
        }

        // Returns the number of signers and the last signer (or zero if the list is empty). Cost increases with the list size
        // returns (signers_len, last_signer)
        fn load() -> (u32, felt) {
            load_from(super::signer_list::read(0))
        }

        fn load_from(from_signer: felt) -> (u32, felt) {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                }
            }
            if (from_signer == 0) {
                // empty list
                return (0_u32, 0);
            }

            let next_signer = super::signer_list::read(from_signer);
            if (next_signer == 0) {
                return (1_u32, from_signer);
            }
            let (next_length, last_signer) = load_from(next_signer);
            return (next_length + 1_u32, last_signer);
        }

        // Returns the number of signers. Cost increases with the list size
        fn get_signers_len() -> u32 {
            get_signers_len_from(super::signer_list::read(0))
        }

        fn get_signers_len_from(from_signer: felt) -> u32 {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                }
            }
            if (from_signer == 0) {
                // empty list
                return 0_u32;
            }
            let next_signer = super::signer_list::read(from_signer);
            let next_length = get_signers_len_from(next_signer);
            return next_length + 1_u32;
        }

        fn get_signers() -> Array<felt> {
            let all_signers = ArrayTrait::new();
            get_signers_from(super::signer_list::read(0), all_signers)
        }

        fn get_signers_from(from_signer: felt, mut previous_signers: Array<felt>) -> Array<felt> {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                }
            }
            if (from_signer == 0) {
                // empty list
                return previous_signers;
            }
            previous_signers.append(from_signer);
            get_signers_from(super::signer_list::read(from_signer), previous_signers)
        }
    }
}

