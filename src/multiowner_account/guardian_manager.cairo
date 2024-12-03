use argent::signer::{
    signer_signature::{
        Signer, SignerTrait, SignerSignature, SignerStorageValue, SignerStorageTrait, SignerSignatureTrait,
        SignerSpanTrait, SignerTypeIntoFelt252, SignerType
    },
};
use argent::utils::linked_set::LinkedSetConfig;
use starknet::storage::{StoragePathEntry, StoragePath,};
use super::events::SignerLinked;


#[starknet::interface]
pub trait IGuardianManager<TContractState> {
    /// @notice Returns the starknet pub key or `0` if there's no guardian. Panics if there are multiple guardians.
    fn get_guardian(self: @TContractState) -> felt252;
    fn get_guardian_guid(self: @TContractState) -> Option<felt252>;
    /// @notice Returns the guardian type if there's any guardian. None if there is no guardian. Panics if there are
    /// multiple guardians.
    fn get_guardian_type(self: @TContractState) -> Option<SignerType>;

    /// @notice Returns the guid of all the guardians
    fn get_guardian_guids(self: @TContractState) -> Array<felt252>;
    // TODO method that returns all the information about the guardians

    fn is_guardian(self: @TContractState, guardian: Signer) -> bool;
    fn is_guardian_guid(self: @TContractState, guardian_guid: felt252) -> bool;

    /// @notice Verifies whether a provided signature is valid and comes from one of the guardians.
    /// @param hash Hash of the message being signed
    /// @param guardian_signature Signature to be verified
    #[must_use]
    fn is_valid_guardian_signature(self: @TContractState, hash: felt252, guardian_signature: SignerSignature) -> bool;
}

#[starknet::interface]
trait IGuardianManagerInternal<TContractState> {
    fn initialize(ref self: TContractState, guardian: Signer);
    fn has_guardian(self: @TContractState) -> bool;

    /// @notice Removes all guardians and optionally adds a new one
    /// @param new_guardian The address of the new guardian, or None to disable the guardian
    fn reset_guardians(ref self: TContractState, replacement_guardian: Option<SignerStorageValue>);

    // /// @notice Adds new guardians to the account
    // /// @dev will revert when trying to add a signer is already an guardian
    // /// @guardians_to_add owners_to_add An array with all the signers to add
    // fn add_guardians(ref self: TContractState, guardians_to_add: Array<Signer>);

    // fn remove_owners(ref self: TContractState, owner_guids_to_remove: Array<felt252>);
    // fn assert_valid_storage(self: @TContractState);
    fn get_single_stark_guardian_pubkey(self: @TContractState) -> Option<felt252>;
    fn get_single_guardian(self: @TContractState) -> Option<SignerStorageValue>;
}

/// Managing the list of owners of the account
#[starknet::component]
mod guardian_manager_component {
    use argent::multiowner_account::owner_manager::{IOwnerManagerCallback, SignerStorageValueLinkedSetConfig};
    use argent::signer::{
        signer_signature::{
            Signer, SignerTrait, SignerSignature, SignerSignatureTrait, SignerSpanTrait, SignerStorageValue,
            SignerStorageTrait, SignerType
        },
    };
    use argent::utils::linked_set_plus_one::{
        LinkedSetPlus1, LinkedSetPlus1ReadImpl, LinkedSetPlus1WriteImpl, MutableLinkedSetPlus1ReadImpl
    };

    use argent::utils::{transaction_version::is_estimate_transaction, asserts::assert_only_self};

    use super::super::events::{SignerLinked, OwnerAddedGuid, OwnerRemovedGuid};
    use super::{IGuardianManager, IGuardianManagerInternal};
    /// Too many signers could make the account unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    struct Storage {
        guardians_storage: LinkedSetPlus1<SignerStorageValue>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event { // TODO XXXXX
    // OwnerAddedGuid: OwnerAddedGuid,
    // OwnerRemovedGuid: OwnerRemovedGuid,
    }

    #[embeddable_as(GuardianManagerImpl)]
    impl GuardianManager<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>, +IOwnerManagerCallback<TContractState>
    > of IGuardianManager<ComponentState<TContractState>> {
        fn get_guardian_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.guardians_storage.get_all_hashes()
        }

        #[inline(always)]
        fn is_guardian(self: @ComponentState<TContractState>, guardian: Signer) -> bool {
            self.guardians_storage.contains(guardian.storage_value())
        }

        #[inline(always)]
        fn is_guardian_guid(self: @ComponentState<TContractState>, guardian_guid: felt252) -> bool {
            self.guardians_storage.contains_by_hash(guardian_guid)
        }

        #[must_use]
        fn is_valid_guardian_signature(
            self: @ComponentState<TContractState>, hash: felt252, guardian_signature: SignerSignature
        ) -> bool {
            if !self.is_guardian(guardian_signature.signer()) {
                return false;
            }
            return guardian_signature.is_valid_signature(hash) || is_estimate_transaction();
        }

        // legacy
        fn get_guardian(self: @ComponentState<TContractState>) -> felt252 {
            // TODO can be improved
            if !self.has_guardian() {
                return 0;
            }
            let guardian = self.get_single_guardian().expect('argent/no-single-guardian');
            assert(!guardian.is_stored_as_guid(), 'argent/only_guid');
            guardian.stored_value
        }

        // legacy
        fn get_guardian_type(self: @ComponentState<TContractState>) -> Option<SignerType> {
            Option::Some(self.get_single_guardian()?.signer_type)
        }

        // legacy
        fn get_guardian_guid(self: @ComponentState<TContractState>) -> Option<felt252> {
            Option::Some(self.get_single_guardian()?.into_guid())
        }
    }

    #[embeddable_as(GuardianManagerInternalImpl)]
    impl GuardianManagerInternal<
        TContractState, +HasComponent<TContractState>, +IOwnerManagerCallback<TContractState>, +Drop<TContractState>
    > of IGuardianManagerInternal<ComponentState<TContractState>> {
        fn initialize(ref self: ComponentState<TContractState>, guardian: Signer) {
            let guid = self.guardians_storage.insert(guardian.storage_value());
            // self.emit_signer_linked_event(SignerLinked { signer_guid: guid, signer: owner });
        }

        fn has_guardian(self: @ComponentState<TContractState>) -> bool {
            !self.guardians_storage.is_empty()
        }

        // fn add_owners(ref self: ComponentState<TContractState>, owners_to_add: Array<Signer>) {
        //     let owner_len = self.owners_storage.len();

        //     self.assert_valid_owner_count(owner_len + owners_to_add.len());
        //     for owner in owners_to_add {
        //         let owner_guid = self.owners_storage.insert(owner.storage_value());
        //         self.emit_owner_added(owner_guid);
        //         self.emit_signer_linked_event(SignerLinked { signer_guid: owner_guid, signer: owner });
        //     };
        // }

        // fn remove_owners(ref self: ComponentState<TContractState>, owner_guids_to_remove: Array<felt252>) {
        //     self.assert_valid_owner_count(self.owners_storage.len() - owner_guids_to_remove.len());

        //     for guid in owner_guids_to_remove {
        //         self.owners_storage.remove(guid);
        //         self.emit_owner_removed(guid);
        //     };
        // }

        fn get_single_guardian(self: @ComponentState<TContractState>) -> Option<SignerStorageValue> {
            self.guardians_storage.single() // TODO consider returning .first() instead for better performance
        }

        fn get_single_stark_guardian_pubkey(self: @ComponentState<TContractState>) -> Option<felt252> {
            self.get_single_guardian()?.starknet_pubkey_or_none()
        }


        fn reset_guardians(ref self: ComponentState<TContractState>, replacement_guardian: Option<SignerStorageValue>) {
            let replacement_guid = if let Option::Some(replacement_guardian) = replacement_guardian {
                replacement_guardian.into_guid()
            } else {
                0
            };
            let mut replacement_was_already_guardian = false;
            let current_guardian_guids = self.guardians_storage.get_all_hashes();
            for current_guardian_guid in current_guardian_guids {
                if current_guardian_guid != replacement_guid {
                    self.guardians_storage.remove(current_guardian_guid);
                    // self.emit_owner_removed(current_guardian_guid); // TODO
                } else {
                    replacement_was_already_guardian = true;
                }
            };
            if !replacement_was_already_guardian {
                if let Option::Some(new_guardian) = replacement_guardian {
                    self.guardians_storage.insert(new_guardian);
                    // self.emit_owner_added(new_guardian_guid);// TODO
                }
            }
        }
    }

    #[generate_trait]
    impl Private<
        TContractState, +HasComponent<TContractState>, +IOwnerManagerCallback<TContractState>, +Drop<TContractState>
    > of PrivateTrait<TContractState> {
        fn assert_valid_guardian_count(self: @ComponentState<TContractState>, signers_len: usize) {
            assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        }
        fn emit_signer_linked_event(ref self: ComponentState<TContractState>, event: SignerLinked) {
            let mut contract = self.get_contract_mut();
            contract.emit_signer_linked_event(event);
        }
        // fn emit_owner_added(ref self: ComponentState<TContractState>, new_owner_guid: felt252) {
    //     self.emit(OwnerAddedGuid { new_owner_guid });
    // }
    // fn emit_owner_removed(ref self: ComponentState<TContractState>, removed_owner_guid: felt252) {
    //     self.emit(OwnerRemovedGuid { removed_owner_guid });
    // }
    }
}
