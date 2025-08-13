use argent::linked_set::linked_set::LinkedSetConfig;

use argent::signer::signer_signature::{Signer, SignerSignature};
use starknet::storage::{StoragePath, StoragePointerReadAccess};

#[starknet::interface]
pub trait ISignerManager<TContractState> {
    /// @notice Change threshold
    /// @dev will revert if invalid threshold
    /// @param new_threshold New threshold
    fn change_threshold(ref self: TContractState, new_threshold: usize);

    /// @notice Adds new signers to the account, additionally sets a new threshold
    /// @dev will revert when trying to add a user already in the list of signers
    /// @dev will revert if invalid threshold
    /// @param new_threshold New threshold
    /// @param signers_to_add An array with all the signers to add
    fn add_signers(ref self: TContractState, new_threshold: usize, signers_to_add: Array<Signer>);

    /// @notice Removes account signers, additionally sets a new threshold
    /// @dev Will revert if any of the signers isn't in the list of signers
    /// @dev will revert if invalid threshold
    /// @param new_threshold New threshold
    /// @param signers_to_remove All the signers to remove
    fn remove_signers(ref self: TContractState, new_threshold: usize, signers_to_remove: Array<Signer>);

    /// @notice Replace one signer with a different one
    /// @dev Will revert when trying to remove a signer that isn't in the list of signers
    /// @dev Will revert when trying to add a signer that is in the list or if the signer is zero
    /// @param signer_to_remove Signer to remove
    /// @param signer_to_add Signer to add
    fn replace_signer(ref self: TContractState, signer_to_remove: Signer, signer_to_add: Signer);

    /// @notice Returns the threshold
    fn get_threshold(self: @TContractState) -> usize;
    /// @notice Returns the guid of all the signers
    fn get_signer_guids(self: @TContractState) -> Array<felt252>;
    fn is_signer(self: @TContractState, signer: Signer) -> bool;
    fn is_signer_guid(self: @TContractState, signer_guid: felt252) -> bool;

    /// @notice Verifies whether a provided signature is valid and comes from one of the multisig owners.
    /// @param hash Hash of the message being signed
    /// @param signer_signature Signature to be verified
    fn is_valid_signer_signature(self: @TContractState, hash: felt252, signer_signature: SignerSignature) -> bool;
}

/// @notice Emitted when the multisig threshold changes
/// @param new_threshold New threshold
#[derive(Drop, starknet::Event)]
pub struct ThresholdUpdated {
    pub new_threshold: usize,
}

/// Emitted when an account owner is added, including when the account is created.
#[derive(Drop, starknet::Event)]
pub struct OwnerAddedGuid {
    #[key]
    pub new_owner_guid: felt252,
}

/// Emitted when an an account owner is removed
#[derive(Drop, starknet::Event)]
pub struct OwnerRemovedGuid {
    #[key]
    pub removed_owner_guid: felt252,
}

/// @notice Config for the linked set of signers. For each signer, we only store the GUID.
impl SignerGuidLinkedSetConfig of LinkedSetConfig<felt252> {
    const END_MARKER: felt252 = 'end';

    fn is_valid_item(self: @felt252) -> bool {
        *self != 0 && *self != Self::END_MARKER
    }

    fn hash(self: @felt252) -> felt252 {
        // No need to hash the value since it is already a hash.
        // We also know that the this function will never return 0 as the guid 0 is invalid
        *self
    }

    fn path_read_value(path: StoragePath<felt252>) -> Option<felt252> {
        let stored_value = path.read();
        if !stored_value.is_valid_item() {
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
pub mod signer_manager_component {
    use argent::linked_set::linked_set::{
        IAddEndMarker, LinkedSet, LinkedSetReadImpl, LinkedSetWriteImpl, MutableLinkedSetReadImpl,
    };
    use argent::multiowner_account::events::SignerLinked;
    use argent::multisig_account::signer_manager::{ISignerManager, OwnerAddedGuid, OwnerRemovedGuid, ThresholdUpdated};
    use argent::signer::{
        signer_signature::{
            Signer, SignerSignature, SignerSignatureTrait, SignerSpanTrait, SignerTrait, starknet_signer_from_pubkey,
        },
    };
    use argent::utils::{asserts::assert_only_self, transaction_version::is_estimate_transaction};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::SignerGuidLinkedSetConfig;

    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    pub struct Storage {
        pub threshold: usize,
        signer_list: LinkedSet<felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ThresholdUpdated: ThresholdUpdated,
        OwnerAddedGuid: OwnerAddedGuid,
        OwnerRemovedGuid: OwnerRemovedGuid,
        SignerLinked: SignerLinked,
    }

    #[embeddable_as(SignerManagerImpl)]
    impl SignerManager<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
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
            self.signer_list.insert_many(guids.span());

            for signer in signers_to_add.span() {
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
            ref self: ComponentState<TContractState>, new_threshold: usize, signers_to_remove: Array<Signer>,
        ) {
            assert_only_self();
            let previous_threshold = self.threshold.read();

            let new_signers_count = self.signer_list.len() - signers_to_remove.len();
            self.assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

            let mut guids = signers_to_remove.span().to_guid_list();
            self.signer_list.remove_many(guids.span());
            for removed_owner_guid in guids {
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
            self.signer_list.remove(signer_to_remove_guid);
            let signer_to_add_guid = self.signer_list.insert(signer_to_add.into_guid());
            assert(signer_to_remove_guid != signer_to_add_guid, 'argent/replace-same-signer');

            self.emit(OwnerRemovedGuid { removed_owner_guid: signer_to_remove_guid });
            self.emit(OwnerAddedGuid { new_owner_guid: signer_to_add_guid });
            self.emit(SignerLinked { signer_guid: signer_to_add_guid, signer: signer_to_add });
        }

        fn get_threshold(self: @ComponentState<TContractState>) -> usize {
            self.threshold.read()
        }

        fn get_signer_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.signer_list.get_all()
        }

        fn is_signer(self: @ComponentState<TContractState>, signer: Signer) -> bool {
            self.signer_list.contains(signer.into_guid())
        }

        fn is_signer_guid(self: @ComponentState<TContractState>, signer_guid: felt252) -> bool {
            self.signer_list.contains(signer_guid)
        }

        fn is_valid_signer_signature(
            self: @ComponentState<TContractState>, hash: felt252, signer_signature: SignerSignature,
        ) -> bool {
            let is_signer = self.signer_list.contains(signer_signature.signer().into_guid());
            assert(is_signer, 'argent/not-a-signer');
            signer_signature.is_valid_signature(hash)
        }
    }

    #[generate_trait]
    pub impl SignerManagerInternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of ISignerManagerInternal<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, threshold: usize, signers: Array<Signer>) {
            assert(self.threshold.read() == 0, 'argent/already-initialized');

            let new_signers_count = signers.len();
            self.assert_valid_threshold_and_signers_count(threshold, new_signers_count);

            let mut guids = signers.span().to_guid_list();
            self.signer_list.insert_many(guids.span());

            for signer in signers {
                let signer_guid = guids.pop_front().unwrap();
                self.emit(OwnerAddedGuid { new_owner_guid: signer_guid });
                self.emit(SignerLinked { signer_guid, signer });
            };

            self.threshold.write(threshold);
            self.emit(ThresholdUpdated { new_threshold: threshold });
        }

        fn assert_valid_threshold_and_signers_count(
            self: @ComponentState<TContractState>, threshold: usize, signers_len: usize,
        ) {
            assert(threshold != 0, 'argent/invalid-threshold');
            assert(signers_len != 0, 'argent/invalid-signers-len');
            assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
            assert(threshold <= signers_len, 'argent/bad-threshold');
        }

        fn assert_valid_storage(self: @ComponentState<TContractState>) {
            self.assert_valid_threshold_and_signers_count(self.threshold.read(), self.signer_list.len());
        }

        fn is_valid_signature_with_threshold(
            self: @ComponentState<TContractState>,
            hash: felt252,
            threshold: u32,
            mut signer_signatures: Array<SignerSignature>,
        ) -> bool {
            assert(signer_signatures.len() == threshold, 'argent/signature-invalid-length');
            let mut last_signer: u256 = 0;
            loop {
                let signer_sig = match signer_signatures.pop_front() {
                    Option::Some(signer_sig) => signer_sig,
                    Option::None => { break true; },
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

        fn migrate_from_pubkeys_to_guids(ref self: ComponentState<TContractState>) {
            // assert valid storage
            let pubkeys = self.get_signer_guids();
            self.assert_valid_threshold_and_signers_count(self.threshold.read(), pubkeys.len());

            // Converting storage from public keys to guid
            let mut signers_to_add = array![];
            for pubkey in pubkeys.span() {
                let starknet_signer = starknet_signer_from_pubkey(*pubkey);
                let signer_guid = starknet_signer.into_guid();
                signers_to_add.append(signer_guid);
                self.emit(SignerLinked { signer_guid, signer: starknet_signer });
            };

            self.signer_list.remove_many(pubkeys.span());
            self.signer_list.insert_many(signers_to_add.span());
        }

        fn add_end_marker(ref self: ComponentState<TContractState>) {
            // Health checks
            let pubkeys = self.get_signer_guids();
            self.assert_valid_threshold_and_signers_count(self.threshold.read(), pubkeys.len());

            self.signer_list.add_end_marker();
        }
    }
}
