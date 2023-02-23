#[contract]
mod ArgentMultisigAccount {
    use array::ArrayTrait;
    use contracts::asserts;
    use traits::Into;
    use traits::TryInto;
    use zeroable::Zeroable;
    use option::OptionTrait;

    // for some reason this is not part of the framework
    impl StorageAccessU32 of starknet::StorageAccess::<u32> {
        fn read(address_domain: felt, base: starknet::StorageBaseAddress) -> starknet::SyscallResult::<u32> {
            Result::Ok(
                starknet::StorageAccess::<felt>::read(address_domain, base)?.try_into().expect('StorageAccessU32 - non u32')
            )
        }
        #[inline(always)]
        fn write(address_domain: felt, base: starknet::StorageBaseAddress, value: u32) -> starknet::SyscallResult::<()> {
            starknet::StorageAccess::<felt>::write(address_domain, base, value.into())
        }
    }

    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    struct Storage {
        threshold: u32,
        signer_list: LegacyMap::<felt, felt>,
    }

    #[event]
    fn ConfigurationUpdated(
        new_threshold: u32,
        new_signers_count: u32,
        added_signers: Array::<felt>,
        removed_signers: Array::<felt>
    ) {}

    // @dev Set the initial parameters for the multisig. It's mandatory to call this methods to secure the account.
    // It's recommended to call this method in the same transaction that deploys the account to make sure it's always initialized
    #[external]
    fn initialize(threshold: u32, signers: Array::<felt>) {
        let current_threshold = threshold::read();
        assert(current_threshold == 0_u32, 'argent/already-initialized');

        let signers_len = signers.len();
        assert_valid_threshold_and_signers_count(threshold, signers_len);

        signers_storage::add_signers(signers, 0);
        threshold::write(threshold);
    // ConfigurationUpdated(); Can't call yet
    }

    // ERC165
    #[view]
    fn supports_interface(interface_id: felt) -> bool {
        interface_id == ERC165_IERC165_INTERFACE_ID | interface_id == ERC165_ACCOUNT_INTERFACE_ID | interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID
    }

    #[view]
    fn get_threshold() -> u32 {
        threshold::read()
    }

    #[view]
    fn get_signers() -> Array::<felt> {
        return signers_storage::get_signers();
    }

    #[view]
    fn is_signer(signer: felt) -> bool {
        return signers_storage::is_signer(signer);
    }


    #[external]
    fn change_threshold(new_threshold: u32) {
        asserts::assert_only_self();

        let signers_len = signers_storage::get_signers_len();

        assert_valid_threshold_and_signers_count(new_threshold, signers_len);
        threshold::write(new_threshold);

        // ConfigurationUpdated(); // TODO
    }

    // @dev Adds new signers to the account, additionally sets a new threshold
    // @param new_threshold New threshold
    // @param signers_to_add Contains the new signers, it will revert if it contains any existing signer
    #[external]
    fn add_signers(new_threshold: u32, signers_to_add: Array::<felt>) {
        asserts::assert_only_self();
        let (signers_len, last_signer) = signers_storage::load();

        let new_signers_len = signers_len + signers_to_add.len();

        assert_valid_threshold_and_signers_count(new_threshold, new_signers_len);

        signers_storage::add_signers(signers_to_add, last_signer);
        threshold::write(new_threshold);
    // ConfigurationUpdated(); // TODO
    }

    /////////////////////////////////////////////////////////
    // INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////

    // Asserts that:  0 < threshold <= signers_len
    fn assert_valid_threshold_and_signers_count(threshold: u32, signers_len: u32) {
        assert(threshold != 0_u32, 'argent/invalid threshold');
        // assert(threshold < max_range, 'argent/invalid threshold');
        assert(signers_len != 0_u32, 'argent/invalid signers len');
        assert(threshold <= signers_len, 'argent/bad threshold');
    }

    fn assert_initialized() {
        let threshold = storage_threshold::read();
        assert(threshold != 0, 'argent/not initialized');
    }

    mod signers_storage {
        use array::ArrayTrait;


        // Returns the number of signers and the last signer (or zero if the list is empty). Cost increases with the list size
        // returns (signers_len, last_signer)
        fn load() -> (u32, felt) {
            return load_from(super::signer_list::read(0));
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
            let (next_lenght, last_signer) = load_from(next_signer);
            return (next_lenght + 1_u32, last_signer);
        }

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

        fn add_signers(mut signers_to_add: Array::<felt>, last_signer: felt) {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                },
            }

            match signers_to_add.pop_front() {
                Option::Some(signer) => {
                    assert(signer != 0, 'argent/invalid zero signer');

                    let current_signer_status = is_signer_using_last(signer, last_signer);
                    assert(!(current_signer_status), 'argent/already a signer');

                    // Signers are added at the end of the list
                    super::signer_list::write(last_signer, signer);

                    add_signers(signers_to_add, signer);
                },
                Option::None(()) => (),
            }
        }

        fn remove_signers(mut signers_to_remove: Array::<felt>, last_signer: felt) {
            match get_gas_all(get_builtin_costs()) {
                Option::Some(_) => {},
                Option::None(_) => {
                    let mut err_data = array_new();
                    array_append(ref err_data, 'Out of gas');
                    panic(err_data)
                },
            }

            match signers_to_remove.pop_front() {
                Option::Some(signer) => {
                    let current_signer_status = is_signer_using_last(signer, last_signer);
                    assert(current_signer_status, 'argent/ not a signer');
                    // Signer pointer set to 0, Previous pointer set to the next in the list

                    let (previous_signer) = find_signer_before(signer);
                    let (next_signer) = signer_list.read(signer);

                    signer_list.write(previous_signer, next_signer);

                    if (next_signer == 0) {
                        // Removing the last item
                        remove_signers(
                            signers_to_remove_len = signers_to_remove_len - 1,
                            signers_to_remove = signers_to_remove + 1,
                            last_signer = previous_signer
                        );
                    } else {
                        // Removing an item in the middle
                        signer_list.write(signer, 0);
                        remove_signers(
                            signers_to_remove_len = signers_to_remove_len - 1,
                            signers_to_remove = signers_to_remove + 1,
                            last_signer = last_signer
                        );
                    }
                },
                Option::None(()) => (),
            }
        }

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

        // Return the last signer or zero if no signers. Cost increases with the list size
        fn find_last_signer() -> felt {
            let first_signer = super::signer_list::read(0);
            return find_last_signer_recursive(first_signer);
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
            return find_last_signer_recursive(next_signer);
        }

        // Returns the signer before `signer_after` or 0 if the signer is the first one. 
        // Reverts if `signer_after` is not found
        // Cost increases with the list size
        fn find_signer_before(signer_after: felt) -> felt {
            return find_signer_before_recursive(signer_after, 0);
        }

        fn find_signer_before_recursive(signer_after: felt, from_signer: felt) -> felt {
            let next_signer = super::signer_list::read(from_signer);
            assert(next_signer != 0, 'argent/ unable to find signer before');

            if (next_signer == signer_after) {
                return from_signer;
            }
            return find_signer_before_recursive(signer_after, next_signer);
        }

        // Returns the number of signers. Cost increases with the list size
        fn get_signers_len() -> u32 {
            return get_signers_len_from(super::signer_list::read(0));
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
            let next_lenght = get_signers_len_from(next_signer);
            return next_lenght + 1_u32;
        }

        fn get_signers() -> Array::<felt> {
            return get_signers_from(super::signer_list::read(0), array_new());
        }

        fn get_signers_from(
            from_signer: felt, mut previous_signers: Array::<felt>
        ) -> Array::<felt> {
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
            return get_signers_from(super::signer_list::read(from_signer), previous_signers);
        }
    }
}

