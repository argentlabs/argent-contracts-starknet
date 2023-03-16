// This module handles the storage of the multisig owners using a linked list
// you can't store signer 0 and you can't store duplicates.
// This allows to retrieve the list of owners easily.
// In terms of storage this will use one storage slot per signer
// Reading become a bit more expensive for some operations as it need to go through the full list for some operations
#[contract]
mod SignersStorage {
    use array::ArrayTrait;
    use array::SpanTrait;
    use gas::get_gas_all;

    struct Storage {
        signer_list: LegacyMap<felt252, felt252>, 
    }

    // Constant computation cost if `signer` is in fact in the list AND it's not the last one.
    // Otherwise cost increases with the list size
    fn is_signer(signer: felt252) -> bool {
        if (signer == 0) {
            return false;
        }
        let next_signer = signer_list::read(signer);
        if (next_signer != 0) {
            return true;
        }
        // check if its the latest
        let last_signer = find_last_signer();

        last_signer == signer
    }

    // Optimized version of `is_signer` with constant compute cost. To use when you know the last signer
    fn is_signer_using_last(signer: felt252, last_signer: felt252) -> bool {
        if (signer == 0) {
            return false;
        }

        let next_signer = signer_list::read(signer);
        if (next_signer != 0) {
            return true;
        }

        last_signer == signer
    }

    // Return the last signer or zero if no signers. Cost increases with the list size
    fn find_last_signer() -> felt252 {
        let first_signer = signer_list::read(0);
        find_last_signer_recursive(first_signer)
    }

    fn find_last_signer_recursive(from_signer: felt252) -> felt252 {
        match get_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = ArrayTrait::new();
                array_append(ref err_data, 'Out of gas');
                panic(err_data)
            },
        }

        let next_signer = signer_list::read(from_signer);
        if (next_signer == 0) {
            return from_signer;
        }
        find_last_signer_recursive(next_signer)
    }

    // Returns the signer before `signer_after` or 0 if the signer is the first one. 
    // Reverts if `signer_after` is not found
    // Cost increases with the list size
    fn find_signer_before(signer_after: felt252) -> felt252 {
        find_signer_before_recursive(signer_after, 0)
    }

    fn find_signer_before_recursive(signer_after: felt252, from_signer: felt252) -> felt252 {
        match get_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = ArrayTrait::new();
                array_append(ref err_data, 'Out of gas');
                panic(err_data)
            },
        }

        let next_signer = signer_list::read(from_signer);
        assert(next_signer != 0, 'argent/cant-find-signer-before');

        if (next_signer == signer_after) {
            return from_signer;
        }
        find_signer_before_recursive(signer_after, next_signer)
    }

    fn add_signers(mut signers_to_add: Span<felt252>, last_signer: felt252) {
        match get_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = ArrayTrait::new();
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
                signer_list::write(last_signer, signer);

                add_signers(signers_to_add, signer);
            },
            Option::None(()) => (),
        }
    }

    fn remove_signers(mut signers_to_remove: Span<felt252>, last_signer: felt252) {
        match get_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = ArrayTrait::new();
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
                let next_signer = signer_list::read(signer);

                signer_list::write(previous_signer, next_signer);

                if (next_signer == 0) {
                    // Removing the last item
                    remove_signers(signers_to_remove, previous_signer);
                } else {
                    // Removing an item in the middle
                    signer_list::write(signer, 0);
                    remove_signers(signers_to_remove, last_signer);
                }
            },
            Option::None(()) => (),
        }
    }

    fn replace_signer(signer_to_remove: felt252, signer_to_add: felt252, last_signer: felt252) {
        assert(signer_to_add != 0, 'argent/invalid-zero-signer');

        let signer_to_add_status = is_signer_using_last(signer_to_add, last_signer);
        assert(!signer_to_add_status, 'argent/already-a-signer');

        let signer_to_remove_status = is_signer_using_last(signer_to_remove, last_signer);
        assert(signer_to_remove_status, 'argent/not-a-signer');

        // removed signer will point to 0
        // previous signer will point to the new one
        // new signer will point to the next one
        let previous_signer = find_signer_before(signer_to_remove);
        let next_signer = signer_list::read(signer_to_remove);

        signer_list::write(signer_to_remove, 0);
        signer_list::write(previous_signer, signer_to_add);
        signer_list::write(signer_to_add, next_signer);
    }

    // Returns the number of signers and the last signer (or zero if the list is empty). Cost increases with the list size
    // returns (signers_len, last_signer)
    fn load() -> (usize, felt252) {
        load_from(signer_list::read(0))
    }

    fn load_from(from_signer: felt252) -> (usize, felt252) {
        match get_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = ArrayTrait::new();
                array_append(ref err_data, 'Out of gas');
                panic(err_data)
            }
        }
        if (from_signer == 0) {
            // empty list
            return (0_usize, 0);
        }

        let next_signer = signer_list::read(from_signer);
        if (next_signer == 0) {
            return (1_usize, from_signer);
        }
        let (next_length, last_signer) = load_from(next_signer);
        (next_length + 1_usize, last_signer)
    }

    // Returns the number of signers. Cost increases with the list size
    fn get_signers_len() -> usize {
        get_signers_len_from(signer_list::read(0))
    }

    fn get_signers_len_from(from_signer: felt252) -> usize {
        match get_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = ArrayTrait::new();
                array_append(ref err_data, 'Out of gas');
                panic(err_data)
            }
        }
        if (from_signer == 0) {
            // empty list
            return 0_usize;
        }
        let next_signer = signer_list::read(from_signer);
        let next_length = get_signers_len_from(next_signer);
        next_length + 1_usize
    }

    fn get_signers() -> Array<felt252> {
        let all_signers = ArrayTrait::new();
        get_signers_from(signer_list::read(0), all_signers)
    }

    fn get_signers_from(
        from_signer: felt252, mut previous_signers: Array<felt252>
    ) -> Array<felt252> {
        match get_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = ArrayTrait::new();
                array_append(ref err_data, 'Out of gas');
                panic(err_data)
            }
        }
        if (from_signer == 0) {
            // empty list
            return previous_signers;
        }
        previous_signers.append(from_signer);
        get_signers_from(signer_list::read(from_signer), previous_signers)
    }
}

