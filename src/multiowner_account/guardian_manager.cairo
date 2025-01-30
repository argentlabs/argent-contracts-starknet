use argent::signer::signer_signature::{Signer, SignerSignature, SignerStorageValue, SignerType};

#[starknet::interface]
pub trait IGuardianManager<TContractState> {
    /// @notice Returns the starknet pub key or 0 if there's no guardian.
    /// @dev Panics if there are multiple guardians.
    fn get_guardian(self: @TContractState) -> felt252;
    fn get_guardian_guid(self: @TContractState) -> Option<felt252>;
    /// @notice Returns the guardian type if there's any guardian. None if there is no guardian.
    /// @dev Panics if there are multiple guardians.
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
    /// @notice Initializes the contract with the first guardian. Should ony be called in the constructor
    /// @param guardian The first guardian of the account
    /// @return The guid of the guardian
    fn initialize(ref self: TContractState, guardian: Signer) -> felt252;
    fn migrate_guardians_storage(ref self: TContractState, guardians: Array<SignerStorageValue>);

    fn has_guardian(self: @TContractState) -> bool;

    /// @notice Removes all guardians and optionally adds a new one
    /// @param new_guardian The address of the new guardian, or None to disable the guardian
    fn reset_guardians(ref self: TContractState, replacement_guardian: Option<SignerStorageValue>);

    /// @notice Add new guardians to the account
    /// @dev will revert when trying to add a signer is already a guardian
    /// @param guardians_to_add An array with all the signers to add
    fn add_guardians(ref self: TContractState, guardians_to_add: Array<Signer>);


    /// @notice Remove guardians to the account
    /// @dev will revert when trying to remove a signer that isn't a guardian
    /// @param guardian_guids_to_remove An array with all the guids to remove
    fn remove_guardians(ref self: TContractState, guardian_guids_to_remove: Array<felt252>);

    fn get_single_stark_guardian_pubkey(self: @TContractState) -> Option<felt252>;
    fn get_single_guardian(self: @TContractState) -> Option<SignerStorageValue>;
    fn assert_valid_storage(self: @TContractState);
}

/// Managing the account guardians
#[starknet::component]
mod guardian_manager_component {
    use argent::account::interface::IEmitArgentAccountEvent;
    use argent::multiowner_account::argent_account::ArgentAccount::Event as ArgentAccountEvent;
    use argent::multiowner_account::events::{GuardianAddedGuid, GuardianRemovedGuid, SignerLinked};
    use argent::multiowner_account::signer_storage_linked_set::SignerStorageValueLinkedSetConfig;
    use argent::signer::signer_signature::{
        Signer, SignerSignature, SignerSignatureTrait, SignerStorageTrait, SignerStorageValue, SignerTrait, SignerType,
    };
    use argent::utils::linked_set_with_head::{
        LinkedSetWithHead, LinkedSetWithHeadReadImpl, LinkedSetWithHeadWriteImpl, MutableLinkedSetWithHeadReadImpl,
    };
    use argent::utils::transaction_version::is_estimate_transaction;
    use super::{IGuardianManager, IGuardianManagerInternal};

    /// Too many signers could make the account unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    struct Storage {
        guardians_storage: LinkedSetWithHead<SignerStorageValue>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GuardianAddedGuid: GuardianAddedGuid,
        GuardianRemovedGuid: GuardianRemovedGuid,
    }

    #[embeddable_as(GuardianManagerImpl)]
    impl GuardianManager<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>, +IEmitArgentAccountEvent<TContractState>,
    > of IGuardianManager<ComponentState<TContractState>> {
        fn get_guardian_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.guardians_storage.get_all_hashes()
        }

        #[inline(always)]
        fn is_guardian(self: @ComponentState<TContractState>, guardian: Signer) -> bool {
            self.guardians_storage.contains(guardian.storage_value())
        }

        fn is_guardian_guid(self: @ComponentState<TContractState>, guardian_guid: felt252) -> bool {
            self.guardians_storage.contains_by_hash(guardian_guid)
        }

        #[must_use]
        fn is_valid_guardian_signature(
            self: @ComponentState<TContractState>, hash: felt252, guardian_signature: SignerSignature,
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
        TContractState, +HasComponent<TContractState>, +IEmitArgentAccountEvent<TContractState>, +Drop<TContractState>,
    > of IGuardianManagerInternal<ComponentState<TContractState>> {
        fn initialize(ref self: ComponentState<TContractState>, guardian: Signer) -> felt252 {
            let guid = self.guardians_storage.insert(guardian.storage_value());
            self.emit_signer_linked_event(SignerLinked { signer_guid: guid, signer: guardian });
            self.emit_guardian_added(guid);
            guid
        }

        fn migrate_guardians_storage(ref self: ComponentState<TContractState>, guardians: Array<SignerStorageValue>) {
            assert(self.guardians_storage.is_empty(), 'argent/guardians-already-init');

            self.assert_valid_guardian_count(guardians.len());
            for guardian in guardians {
                let guardian_guid = self.guardians_storage.insert(guardian);
                self.emit_guardian_added(guardian_guid);
            };
        }

        fn has_guardian(self: @ComponentState<TContractState>) -> bool {
            !self.guardians_storage.is_empty()
        }

        fn add_guardians(ref self: ComponentState<TContractState>, guardians_to_add: Array<Signer>) {
            let guardians_len = self.guardians_storage.len();

            self.assert_valid_guardian_count(guardians_len + guardians_to_add.len());
            for guardian in guardians_to_add {
                let guardian_guid = self.guardians_storage.insert(guardian.storage_value());
                self.emit_guardian_added(guardian_guid);
                self.emit_signer_linked_event(SignerLinked { signer_guid: guardian_guid, signer: guardian });
            };
        }

        fn remove_guardians(ref self: ComponentState<TContractState>, guardian_guids_to_remove: Array<felt252>) {
            self.assert_valid_guardian_count(self.guardians_storage.len() - guardian_guids_to_remove.len());

            for guid in guardian_guids_to_remove {
                self.guardians_storage.remove(guid);
                self.emit_guardian_removed(guid);
            };
        }

        fn get_single_guardian(self: @ComponentState<TContractState>) -> Option<SignerStorageValue> {
            self.guardians_storage.single()
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
                    self.emit_guardian_removed(current_guardian_guid);
                } else {
                    replacement_was_already_guardian = true;
                }
            };
            if !replacement_was_already_guardian {
                if let Option::Some(new_guardian) = replacement_guardian {
                    let new_guardian_guid = self.guardians_storage.insert(new_guardian);
                    self.emit_guardian_added(new_guardian_guid);
                }
            }
        }

        fn assert_valid_storage(self: @ComponentState<TContractState>) {
            self.assert_valid_guardian_count(self.guardians_storage.len());
        }
    }

    #[generate_trait]
    impl Private<
        TContractState, +HasComponent<TContractState>, +IEmitArgentAccountEvent<TContractState>, +Drop<TContractState>,
    > of PrivateTrait<TContractState> {
        fn assert_valid_guardian_count(self: @ComponentState<TContractState>, signers_len: usize) {
            assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        }

        fn emit_signer_linked_event(ref self: ComponentState<TContractState>, event: SignerLinked) {
            let mut contract = self.get_contract_mut();
            contract.emit_event_callback(ArgentAccountEvent::SignerLinked(event));
        }

        fn emit_guardian_added(ref self: ComponentState<TContractState>, new_guardian_guid: felt252) {
            self.emit(GuardianAddedGuid { new_guardian_guid });
        }
        fn emit_guardian_removed(ref self: ComponentState<TContractState>, removed_guardian_guid: felt252) {
            self.emit(GuardianRemovedGuid { removed_guardian_guid });
        }
    }
}
