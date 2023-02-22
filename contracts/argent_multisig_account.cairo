#[contract]
mod ArgentMultisigAccount {
    use array::ArrayTrait;
    use traits::Into;
    use zeroable::Zeroable;


    struct Storage {
        threshold: felt,
        signer_list: LegacyMap::<felt, felt>,
    }


    #[event]
    fn ConfigurationUpdated(
        new_threshold: felt,
        new_signers_count: felt,
        added_singers_len: felt,
        added_signers: Array::<felt>,
        removed_signers_len: felt,
        removed_signers: Array::<felt>
    ) {}

    // @dev Set the initial parameters for the multisig. It's mandatory to call this methods to secure the account.
    // It's recommended to call this method in the same transaction that deploys the account to make sure it's always initialized
    #[external]
    fn initialize(threshold: felt, signers: Array::<felt>) {
        let current_threshold = threshold::read();
        assert(current_threshold.is_zero(), 'argent/already-initialized');

        let signers_len = signers.len();
        assert_valid_threshold_and_signers_count(threshold, signers_len);

        add_signers(signers, 0);
        threshold::write(threshold);

    // ConfigurationUpdated(); Can't call yet
    }


    #[view]
    fn get_threshold() -> felt {
        storage_threshold::read()
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

        last_signer == signer
    }

    fn add_signers(mut signers_to_add: Array::<felt>, last_signer: felt) {
        match get_gas() {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut data = ArrayTrait::new();
                data.append('Out of gas');
                panic(data);
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

    // Asserts that:  0 < threshold <= signers_len
    fn assert_valid_threshold_and_signers_count(threshold: felt, signers_len: usize) {
        assert(threshold != 0, 'argent/invalid threshold');
        // assert(threshold < max_range, 'argent/invalid threshold');
        assert(signers_len != 0_u32, 'argent/invalid signers len');
        assert(threshold <= signers_len.into(), 'argent/bad threshold');
    }
}
