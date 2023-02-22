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

        add_signers(signers, 0);
        threshold::write(threshold);
    // ConfigurationUpdated(); Can't call yet
    }


    #[external]
    fn change_threshold(new_threshold: u32) {
        asserts::assert_only_self();

        let signers_len = get_signers_len();

        assert_valid_threshold_and_signers_count(new_threshold, signers_len);
        threshold::write(new_threshold);

        // ConfigurationUpdated(); // TODO
    }


    #[view]
    fn get_threshold() -> u32 {
        threshold::read()
    }

    // ERC165
    #[view]
    fn supports_interface(interface_id: felt) -> bool {
        interface_id == ERC165_IERC165_INTERFACE_ID | interface_id == ERC165_ACCOUNT_INTERFACE_ID | interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID
    }

    fn is_signer_using_last(signer: felt, last_signer: felt) -> bool {
        if (signer == 0) {
            return false;
        }

        let next_signer = signer_list::read(signer);
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
                signer_list::write(last_signer, signer);

                add_signers(signers_to_add, signer);
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
        let next_signer = signer_list::read(signer);
        if (next_signer != 0) {
            return true;
        }
        // check if its the latest
        let last_signer = find_last_signer();
        return last_signer == signer;
    }

    // Return the last signer or zero if no signers. Cost increases with the list size
    fn find_last_signer() -> felt {
        let first_signer = signer_list::read(0);
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

        let next_signer = signer_list::read(from_signer);
        if (next_signer == 0) {
            return from_signer;
        }
        return find_last_signer_recursive(next_signer);
    }

    // Returns the number of signers. Cost increases with the list size
    fn get_signers_len() -> u32 {
        return get_signers_len_from(signer_list::read(0));
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
        let next_signer = signer_list::read(from_signer);
        let next_lenght = get_signers_len_from(next_signer);
        return next_lenght + 1_u32;
    }

    // Asserts that:  0 < threshold <= signers_len
    fn assert_valid_threshold_and_signers_count(threshold: u32, signers_len: u32) {
        assert(threshold != 0_u32, 'argent/invalid threshold');
        // assert(threshold < max_range, 'argent/invalid threshold');
        assert(signers_len != 0_u32, 'argent/invalid signers len');
        assert(threshold <= signers_len, 'argent/bad threshold');
    }
}
