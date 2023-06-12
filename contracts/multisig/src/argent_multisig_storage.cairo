// This module handles the storage of the multisig owners using a linked set
// you can't store signer 0 and you can't store duplicates.
// This allows to retrieve the list of owners easily.
// In terms of storage this will use one storage slot per signer
// Reading become a bit more expensive for some operations as it need to go through the full list for some operations
#[starknet::contract]
mod MultisigStorage {
    use array::{ArrayTrait, SpanTrait};
    use starknet::ClassHash;

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Storage                                           //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    struct Storage {
        signer_list: LegacyMap<felt252, felt252>,
        threshold: usize,
        outside_nonces: LegacyMap<felt252, bool>,
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    //                                          Internal                                          //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // Constant computation cost if `signer` is in fact in the list AND it's not the last one.
    // Otherwise cost increases with the list size
    fn is_signer(signer: felt252) -> bool {
        if signer == 0 {
            return false;
        }
        let next_signer = signer_list::read(signer);
        if next_signer != 0 {
            return true;
        }
        // check if its the latest
        let last_signer = find_last_signer();

        last_signer == signer
    }

    // Optimized version of `is_signer` with constant compute cost. To use when you know the last signer
    fn is_signer_using_last(signer: felt252, last_signer: felt252) -> bool {
        if signer == 0 {
            return false;
        }

        let next_signer = signer_list::read(signer);
        if next_signer != 0 {
            return true;
        }

        last_signer == signer
    }

    // Return the last signer or zero if no signers. Cost increases with the list size
    fn find_last_signer() -> felt252 {
        let mut current_signer = signer_list::read(0);
        loop {
            let next_signer = signer_list::read(current_signer);
            if next_signer == 0 {
                break current_signer;
            }
            current_signer = next_signer;
        }
    }

    // Returns the signer before `signer_after` or 0 if the signer is the first one. 
    // Reverts if `signer_after` is not found
    // Cost increases with the list size
    fn find_signer_before(signer_after: felt252) -> felt252 {
        let mut current_signer = 0;
        loop {
            let next_signer = signer_list::read(current_signer);
            assert(next_signer != 0, 'argent/cant-find-signer-before');

            if next_signer == signer_after {
                break current_signer;
            }
            current_signer = next_signer;
        }
    }

    fn add_signers(mut signers_to_add: Span<felt252>, last_signer: felt252) {
        match signers_to_add.pop_front() {
            Option::Some(signer_ref) => {
                let signer = *signer_ref;
                assert(signer != 0, 'argent/invalid-zero-signer');

                let current_signer_status = is_signer_using_last(signer, last_signer);
                assert(!current_signer_status, 'argent/already-a-signer');

                // Signers are added at the end of the list
                signer_list::write(last_signer, signer);

                add_signers(signers_to_add, last_signer: signer);
            },
            Option::None(()) => (),
        }
    }

    fn remove_signers(mut signers_to_remove: Span<felt252>, last_signer: felt252) {
        match signers_to_remove.pop_front() {
            Option::Some(signer_ref) => {
                let signer = *signer_ref;
                let current_signer_status = is_signer_using_last(signer, last_signer);
                assert(current_signer_status, 'argent/not-a-signer');

                // Signer pointer set to 0, Previous pointer set to the next in the list

                let previous_signer = find_signer_before(signer);
                let next_signer = signer_list::read(signer);

                signer_list::write(previous_signer, next_signer);

                if next_signer == 0 {
                    // Removing the last item
                    remove_signers(signers_to_remove, last_signer: previous_signer);
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
        let mut current_signer = 0;
        let mut size = 0;
        loop {
            let next_signer = signer_list::read(current_signer);
            if next_signer == 0 {
                break (size, current_signer);
            }
            current_signer = next_signer;
            size += 1;
        }
    }


    // Returns the number of signers. Cost increases with the list size
    fn get_signers_len() -> usize {
        let mut current_signer = signer_list::read(0);
        let mut size = 0;
        loop {
            if current_signer == 0 {
                break size;
            }
            current_signer = signer_list::read(current_signer);
            size += 1;
        }
    }

    fn get_signers() -> Array<felt252> {
        let mut current_signer = signer_list::read(0);
        let mut signers = ArrayTrait::new();
        loop {
            if current_signer == 0 {
                // Can't break signers atm because "variable was previously moved"
                break ();
            }
            signers.append(current_signer);
            current_signer = signer_list::read(current_signer);
        };
        signers
    }

    fn get_threshold() -> usize {
        threshold::read()
    }

    fn set_threshold(threshold: usize) {
        threshold::write(threshold);
    }

    fn get_outside_nonce(nonce: felt252) -> bool {
        outside_nonces::read(nonce)
    }

    fn set_outside_nonce(nonce: felt252, used: bool) {
        outside_nonces::write(nonce, used)
    }
}

