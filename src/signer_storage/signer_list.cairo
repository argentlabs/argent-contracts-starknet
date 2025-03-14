#[starknet::component]
mod signer_list_component {
    use argent::signer::signer_signature::Signer;
    use argent::signer_storage::interface::ISignerList;
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        signer_list: Map<felt252, felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnerAddedGuid: OwnerAddedGuid,
        OwnerRemovedGuid: OwnerRemovedGuid,
        SignerLinked: SignerLinked,
    }

    /// Emitted when an account owner is added, including when the account is created.
    #[derive(Drop, starknet::Event)]
    struct OwnerAddedGuid {
        #[key]
        new_owner_guid: felt252,
    }

    /// Emitted when an an account owner is removed
    #[derive(Drop, starknet::Event)]
    struct OwnerRemovedGuid {
        #[key]
        removed_owner_guid: felt252,
    }

    /// @notice Emitted when a signer is added to link its details with its GUID
    /// @param signer_guid The signer's GUID
    /// @param signer The signer struct
    #[derive(Drop, starknet::Event)]
    struct SignerLinked {
        #[key]
        signer_guid: felt252,
        signer: Signer,
    }

    #[embeddable_as(SignerListInternalImpl)]
    impl InternalImpl<TContractState, +HasComponent<TContractState>> of ISignerList<ComponentState<TContractState>> {
        #[inline(always)]
        fn is_signer_in_list(self: @ComponentState<TContractState>, signer: felt252) -> bool {
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

        #[inline(always)]
        fn add_signer(ref self: ComponentState<TContractState>, signer_to_add: felt252, last_signer: felt252) {
            assert(signer_to_add != 0, 'argent/invalid-zero-signer');
            let is_signer = self.is_signer_using_last(signer_to_add, last_signer);
            assert(!is_signer, 'argent/already-a-signer');
            // Signers are added at the end of the list
            self.signer_list.write(last_signer, signer_to_add);
        }

        fn add_signers(
            ref self: ComponentState<TContractState>, mut signers_to_add: Span<felt252>, last_signer: felt252,
        ) {
            if let Option::Some(signer_ref) = signers_to_add.pop_front() {
                let signer = *signer_ref;
                self.add_signer(signer_to_add: signer, last_signer: last_signer);
                self.add_signers(signers_to_add, last_signer: signer);
            }
        }

        // Returns the last signer of the list after the removal. This is needed to efficiently remove multiple signers.
        #[inline(always)]
        fn remove_signer(
            ref self: ComponentState<TContractState>, signer_to_remove: felt252, last_signer: felt252,
        ) -> felt252 {
            let is_signer = self.is_signer_using_last(signer_to_remove, last_signer);
            assert(is_signer, 'argent/not-a-signer');

            // Signer pointer set to 0, Previous pointer set to the next in the list
            let previous_signer = self.find_signer_before(signer_to_remove);
            let next_signer = self.signer_list.read(signer_to_remove);

            self.signer_list.write(previous_signer, next_signer);
            if next_signer == 0 {
                // Removing the last item
                previous_signer
            } else {
                // Removing an item in the middle
                self.signer_list.write(signer_to_remove, 0);
                last_signer
            }
        }

        fn remove_signers(
            ref self: ComponentState<TContractState>, mut signers_to_remove: Span<felt252>, mut last_signer: felt252,
        ) {
            for signer_ref in signers_to_remove {
                let signer = *signer_ref;
                last_signer = self.remove_signer(signer_to_remove: signer, last_signer: last_signer);
            }
        }

        #[inline(always)]
        fn replace_signer(
            ref self: ComponentState<TContractState>,
            signer_to_remove: felt252,
            signer_to_add: felt252,
            last_signer: felt252,
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

        // Returns the number of signers and the last signer (or zero if the list is empty). Cost increases with the
        // list size returns (signers_len, last_signer)
        fn load(self: @ComponentState<TContractState>) -> (usize, felt252) {
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
        fn get_signers_len(self: @ComponentState<TContractState>) -> usize {
            let mut current_signer = self.signer_list.read(0);
            let mut size = 0;
            while current_signer.is_non_zero() {
                current_signer = self.signer_list.read(current_signer);
                size += 1;
            }
            size
        }

        fn get_signers(self: @ComponentState<TContractState>) -> Array<felt252> {
            let mut current_signer = self.signer_list.read(0);
            let mut signers = array![];
            while current_signer.is_non_zero() {
                signers.append(current_signer);
                current_signer = self.signer_list.read(current_signer);
            }
            signers
        }

        // Returns true if `first_signer` is before `second_signer` in the signer list.
        fn is_signer_before(
            self: @ComponentState<TContractState>, first_signer: felt252, second_signer: felt252,
        ) -> bool {
            let mut is_before: bool = false;
            let mut current_signer = first_signer;
            loop {
                let next_signer = self.signer_list.read(current_signer);
                if next_signer == 0 {
                    break;
                }
                if next_signer == second_signer {
                    is_before = true;
                    break;
                }
                current_signer = next_signer;
            }
            return is_before;
        }
    }

    #[generate_trait]
    impl Private<TContractState, +HasComponent<TContractState>> of PrivateTrait<TContractState> {
        // Optimized version of `is_signer` with constant compute cost. To use when you know the last signer
        #[inline(always)]
        fn is_signer_using_last(self: @ComponentState<TContractState>, signer: felt252, last_signer: felt252) -> bool {
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
        fn find_last_signer(self: @ComponentState<TContractState>) -> felt252 {
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
        fn find_signer_before(self: @ComponentState<TContractState>, signer_after: felt252) -> felt252 {
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
    }
}
