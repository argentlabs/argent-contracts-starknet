use argent::account::interface::Version;
use argent::signer::signer_signature::SignerStorageValue;

#[starknet::interface]
trait IUpgradeMigrationInternal<TContractState> {
    fn migrate_from_before_0_2_0(ref self: TContractState);
    fn migrate_from_0_2_0(ref self: TContractState);
}

trait IUpgradeMigrationCallback<TContractState> {
    fn migrate_owners(ref self: TContractState);
}

#[starknet::component]
mod upgrade_migration_component {
    use argent::account::interface::Version;
    use argent::signer::{signer_signature::{starknet_signer_from_pubkey, SignerTrait}};
    use starknet::storage::Map;
    use super::{IUpgradeMigrationInternal, IUpgradeMigrationCallback};

    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT_LEGACY: usize = 32;

    #[storage]
    struct Storage {
        signer_list: Map<felt252, felt252>,
        threshold: usize,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event { // SignerLinked: SignerLinked,
    }

    #[embeddable_as(UpgradableInternalImpl)]
    impl UpgradableMigrationInternal<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
    > of IUpgradeMigrationInternal<ComponentState<TContractState>> {
        fn migrate_from_before_0_2_0(ref self: ComponentState<TContractState>) {
            // Check basic invariants
            // Not migrated yet to guids
            assert_valid_threshold_and_signers_count(self.threshold.read(), self.get_signers_len());
            let pubkeys = self.get_signers();
            let mut pubkeys_span = pubkeys.span();
            let mut signers_to_add = array![];
            // Converting storage from public keys to guid
            while let Option::Some(pubkey) = pubkeys_span.pop_front() {
                let starknet_signer = starknet_signer_from_pubkey(*pubkey);
                let signer_guid = starknet_signer.into_guid();
                signers_to_add.append(signer_guid);
                // TODO Is this good enough or should we do like the account where we emit 'any' multisig event?
            // self.emit(SignerLinked { signer_guid, signer: starknet_signer });
            };
            let last_signer = *pubkeys[pubkeys.len() - 1];
            self.remove_signers(pubkeys.span(), last_signer);
            self.add_signers(self.threshold.read(), pubkeys);

            self.migrate_from_0_2_0();
        }

        fn migrate_from_0_2_0(ref self: ComponentState<TContractState>) {
            self.migrate_owners();
        }
    }

    #[generate_trait]
    impl Private<
        TContractState,
        +HasComponent<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
        +Drop<TContractState>,
    > of PrivateTrait<TContractState> {
        fn migrate_owners(ref self: ComponentState<TContractState>) {
            let mut contract = self.get_contract_mut();
            contract.migrate_owners();
        }


        // Returns the number of signers. Cost increases with the list size
        fn get_signers_len(self: @ComponentState<TContractState>) -> usize {
            let mut current_signer = self.signer_list.read(0);
            let mut size = 0;
            while current_signer != 0 {
                current_signer = self.signer_list.read(current_signer);
                size += 1;
            };
            size
        }

        // TODO Cheaper returning span?
        fn get_signers(self: @ComponentState<TContractState>) -> Array<felt252> {
            let mut current_signer = self.signer_list.read(0);
            let mut signers = array![];
            while current_signer != 0 {
                signers.append(current_signer);
                current_signer = self.signer_list.read(current_signer);
            };
            signers
        }

        fn add_signers(ref self: ComponentState<TContractState>, new_threshold: usize, signers_to_add: Array<felt252>) {
            let (signers_len, last_signer) = self.load();
            // let previous_threshold = self.threshold.read();

            let new_signers_count = signers_len + signers_to_add.len();
            assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);
            self.add_signers_in(signers_to_add.span(), last_signer);
            self.threshold.write(new_threshold);
            // if previous_threshold != new_threshold {
        //     self.emit(ThresholdUpdated { new_threshold });
        // }

            // let mut signers_added = signers_to_add.span();
        // loop {
        //     match signers_added.pop_front() {
        //         Option::Some(added_signer) => { self.emit(OwnerAdded { new_owner_guid: *added_signer }); },
        //         Option::None(_) => { break; }
        //     };
        // };
        }

        fn add_signers_in(
            ref self: ComponentState<TContractState>, mut signers_to_add: Span<felt252>, last_signer: felt252
        ) {
            match signers_to_add.pop_front() {
                Option::Some(signer_ref) => {
                    let signer = *signer_ref;
                    assert(signer != 0, 'argent/invalid-zero-signer');

                    let current_signer_status = self.is_signer_using_last(signer, last_signer);
                    assert(!current_signer_status, 'argent/already-a-signer');

                    // Signers are added at the end of the list
                    self.signer_list.write(last_signer, signer);

                    self.add_signers_in(signers_to_add, last_signer: signer);
                },
                Option::None(()) => (),
            }
        }

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

        // TODO Copy pasted atm, should we optimized it? as we are reading it just before?
        // Returns the last signer of the list after the removal. This is needed to efficiently remove multiple signers.
        #[inline(always)]
        fn remove_signer(
            ref self: ComponentState<TContractState>, signer_to_remove: felt252, last_signer: felt252
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
            ref self: ComponentState<TContractState>, mut signers_to_remove: Span<felt252>, mut last_signer: felt252
        ) {
            loop {
                let signer = match signers_to_remove.pop_front() {
                    Option::Some(signer) => *signer,
                    Option::None => { break; }
                };
                last_signer = self.remove_signer(signer_to_remove: signer, last_signer: last_signer);
            }
        }

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

    fn assert_valid_threshold_and_signers_count(threshold: usize, signers_len: usize) {
        assert(threshold != 0, 'argent/invalid-threshold');
        assert(signers_len != 0, 'argent/invalid-signers-len');
        assert(signers_len <= MAX_SIGNERS_COUNT_LEGACY, 'argent/invalid-signers-len');
        assert(threshold <= signers_len, 'argent/bad-threshold');
    }
}
