use argent::utils::linked_set::LinkedSetConfig;
use starknet::storage::{StoragePathEntry, StoragePath, StorageBase};

impl SignerGuidLinkedSetConfig of LinkedSetConfig<felt252> {
    const END_MARKER: felt252 = 'end';

    fn is_valid_item(self: @felt252) -> bool {
        *self != 0 && *self != Self::END_MARKER
    }

    fn id(self: @felt252) -> felt252 {
        *self
    }

    fn path_read_value(path: StoragePath<felt252>) -> Option<felt252> {
        let stored_value = path.read();
        if stored_value == 0 || stored_value == Self::END_MARKER {
            return Option::None;
        }
        Option::Some(stored_value)
    }

    fn path_is_in_set(path: StoragePath<felt252>) -> bool {
        path.read() != 0
    }
}

/// @notice Implements the methods of a multisig such as
/// adding or removing signers, changing the threshold, etc
#[starknet::component]
mod signer_manager_component {
    use argent::multisig_account::signer_manager::interface::{ISignerManager, ISignerManagerInternal};
    use argent::signer::{
        signer_signature::{
            Signer, SignerTrait, SignerSignature, SignerSignatureTrait, SignerSpanTrait, starknet_signer_from_pubkey
        },
    };
    use argent::utils::linked_set::{LinkedSet, LinkedSetReadImpl, LinkedSetWriteImpl, MutableLinkedSetReadImpl};
    use argent::utils::{transaction_version::is_estimate_transaction, asserts::assert_only_self};
    use super::SignerGuidLinkedSetConfig;

    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    struct Storage {
        threshold: usize,
        signer_list: LinkedSet<felt252>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ThresholdUpdated: ThresholdUpdated,
        OwnerAddedGuid: OwnerAddedGuid,
        OwnerRemovedGuid: OwnerRemovedGuid,
        SignerLinked: SignerLinked,
    }

    /// @notice Emitted when the multisig threshold changes
    /// @param new_threshold New threshold
    #[derive(Drop, starknet::Event)]
    struct ThresholdUpdated {
        new_threshold: usize,
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

    #[embeddable_as(SignerManagerImpl)]
    impl SignerManager<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of ISignerManager<ComponentState<TContractState>> {
        fn change_threshold(ref self: ComponentState<TContractState>, new_threshold: usize) {
            assert_only_self();
            assert(new_threshold != self.threshold.read(), 'argent/same-threshold');
            let new_signers_count = self.signer_list.len();

            self.assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);
            self.threshold.write(new_threshold);
            self.emit(ThresholdUpdated { new_threshold });
        }

        fn add_signers(ref self: ComponentState<TContractState>, new_threshold: usize, signers_to_add: Array<Signer>) {
            assert_only_self();

            let previous_threshold = self.threshold.read();

            let new_signers_count = self.signer_list.len() + signers_to_add.len();
            self.assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

            let mut guids = signers_to_add.span().to_guid_list();
            self.signer_list.add_items(guids.span());
            let mut signers_to_add_span = signers_to_add.span();
            while let Option::Some(signer) = signers_to_add_span.pop_front() {
                let signer_guid = guids.pop_front().unwrap();
                self.emit(OwnerAddedGuid { new_owner_guid: signer_guid });
                self.emit(SignerLinked { signer_guid, signer: *signer });
            };

            self.threshold.write(new_threshold);
            if previous_threshold != new_threshold {
                self.emit(ThresholdUpdated { new_threshold });
            }
        }

        fn remove_signers(
            ref self: ComponentState<TContractState>, new_threshold: usize, signers_to_remove: Array<Signer>
        ) {
            assert_only_self();
            let previous_threshold = self.threshold.read();

            let new_signers_count = self.signer_list.len() - signers_to_remove.len();
            self.assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

            let mut guids = signers_to_remove.span().to_guid_list();
            self.signer_list.remove_items(guids.span());
            while let Option::Some(removed_owner_guid) = guids.pop_front() {
                self.emit(OwnerRemovedGuid { removed_owner_guid })
            };

            self.threshold.write(new_threshold);
            if previous_threshold != new_threshold {
                self.emit(ThresholdUpdated { new_threshold });
            }
        }

        fn replace_signer(ref self: ComponentState<TContractState>, signer_to_remove: Signer, signer_to_add: Signer) {
            assert_only_self();
            let signer_to_remove_guid = signer_to_remove.into_guid();
            let signer_to_add_guid = signer_to_add.into_guid();
            self.signer_list.replace_item(signer_to_remove_guid, signer_to_add_guid);

            self.emit(OwnerRemovedGuid { removed_owner_guid: signer_to_remove_guid });
            self.emit(OwnerAddedGuid { new_owner_guid: signer_to_add_guid });
            self.emit(SignerLinked { signer_guid: signer_to_add_guid, signer: signer_to_add });
        }

        fn get_threshold(self: @ComponentState<TContractState>) -> usize {
            self.threshold.read()
        }

        fn get_signer_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.signer_list.get_all_ids()
        }

        fn is_signer(self: @ComponentState<TContractState>, signer: Signer) -> bool {
            self.signer_list.is_in(signer.into_guid())
        }

        fn is_signer_guid(self: @ComponentState<TContractState>, signer_guid: felt252) -> bool {
            self.signer_list.is_in(signer_guid)
        }

        fn is_valid_signer_signature(
            self: @ComponentState<TContractState>, hash: felt252, signer_signature: SignerSignature
        ) -> bool {
            let is_signer = self.signer_list.is_in(signer_signature.signer().into_guid());
            assert(is_signer, 'argent/not-a-signer');
            signer_signature.is_valid_signature(hash)
        }
    }

    #[embeddable_as(SignerManagerInternalImpl)]
    impl SignerManagerInternal<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of ISignerManagerInternal<ComponentState<TContractState>> {
        fn initialize(ref self: ComponentState<TContractState>, threshold: usize, mut signers: Array<Signer>) {
            assert(self.threshold.read() == 0, 'argent/already-initialized');

            let new_signers_count = signers.len();
            self.assert_valid_threshold_and_signers_count(threshold, new_signers_count);

            let mut guids = signers.span().to_guid_list();
            self.signer_list.add_items(guids.span());

            while let Option::Some(signer) = signers.pop_front() {
                let signer_guid = guids.pop_front().unwrap();
                self.emit(OwnerAddedGuid { new_owner_guid: signer_guid });
                self.emit(SignerLinked { signer_guid, signer });
            };

            self.threshold.write(threshold);
            self.emit(ThresholdUpdated { new_threshold: threshold });
        }

        fn assert_valid_threshold_and_signers_count(
            self: @ComponentState<TContractState>, threshold: usize, signers_len: usize
        ) {
            assert(threshold != 0, 'argent/invalid-threshold');
            assert(signers_len != 0, 'argent/invalid-signers-len');
            assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
            assert(threshold <= signers_len, 'argent/bad-threshold');
        }

        fn assert_valid_storage(self: @ComponentState<TContractState>) {
            self.assert_valid_threshold_and_signers_count(self.threshold.read(), self.signer_list.len());
        }

        fn migrate_from_pubkeys_to_guids(ref self: ComponentState<TContractState>) {
            // assert valid storage
            let pubkeys = self.get_signer_guids();
            self.assert_valid_threshold_and_signers_count(self.threshold.read(), pubkeys.len());

            // Converting storage from public keys to guid
            let mut pubkeys_span = pubkeys.span();
            let mut signers_to_add = array![];
            while let Option::Some(pubkey) = pubkeys_span.pop_front() {
                let starknet_signer = starknet_signer_from_pubkey(*pubkey);
                let signer_guid = starknet_signer.into_guid();
                signers_to_add.append(signer_guid);
                self.emit(SignerLinked { signer_guid, signer: starknet_signer });
            };

            self.signer_list.remove_items(pubkeys.span());
            self.signer_list.add_items(signers_to_add.span());
        }

        fn is_valid_signature_with_threshold(
            self: @ComponentState<TContractState>,
            hash: felt252,
            threshold: u32,
            mut signer_signatures: Array<SignerSignature>
        ) -> bool {
            assert(signer_signatures.len() == threshold, 'argent/signature-invalid-length');
            let mut last_signer: u256 = 0;
            loop {
                let signer_sig = match signer_signatures.pop_front() {
                    Option::Some(signer_sig) => signer_sig,
                    Option::None => { break true; }
                };
                let signer_guid = signer_sig.signer().into_guid();
                assert(self.is_signer_guid(signer_guid), 'argent/not-a-signer');
                let signer_uint: u256 = signer_guid.into();
                assert(signer_uint > last_signer, 'argent/signatures-not-sorted');
                last_signer = signer_uint;
                if !signer_sig.is_valid_signature(hash) && !is_estimate_transaction() {
                    break false;
                }
            }
        }
    }
}
