use argent::signer::signer_signature::{Signer, SignerInfo, SignerSignature, SignerStorageValue, SignerType};

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
    fn get_guardians_guids(self: @TContractState) -> Array<felt252>;
    fn get_guardians_info(self: @TContractState) -> Array<SignerInfo>;

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


    fn change_guardians(
        ref self: TContractState, guardian_guids_to_remove: Array<felt252>, guardians_to_add: Array<Signer>,
    );

    fn complete_guardian_escape(ref self: TContractState, new_guardian: Option<SignerStorageValue>);

    fn get_single_stark_guardian_pubkey(self: @TContractState) -> Option<felt252>;
    fn get_single_guardian(self: @TContractState) -> Option<SignerStorageValue>;
    fn assert_valid_storage(self: @TContractState);
}

/// Managing the account guardians
#[starknet::component]
pub mod guardian_manager_component {
    use argent::linked_set::linked_set_with_head::{
        LinkedSetWithHead, LinkedSetWithHeadReadImpl, LinkedSetWithHeadWriteImpl, MutableLinkedSetWithHeadReadImpl,
    };
    use argent::multiowner_account::argent_account::ArgentAccount::Event as ArgentAccountEvent;
    use argent::multiowner_account::argent_account::IEmitArgentAccountEvent;
    use argent::multiowner_account::events::{GuardianAddedGuid, GuardianRemovedGuid, SignerLinked};
    use argent::multiowner_account::signer_storage_linked_set::SignerStorageValueLinkedSetConfig;
    use argent::signer::signer_signature::{
        Signer, SignerInfo, SignerSignature, SignerSignatureTrait, SignerStorageTrait, SignerStorageValue, SignerTrait,
        SignerType,
    };
    use argent::utils::array_ext::SpanContains;
    use argent::utils::transaction_version::is_estimate_transaction;
    use super::{IGuardianManager, IGuardianManagerInternal};

    /// Too many signers could make the account unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    pub struct Storage {
        guardians_storage: LinkedSetWithHead<SignerStorageValue>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        GuardianAddedGuid: GuardianAddedGuid,
        GuardianRemovedGuid: GuardianRemovedGuid,
    }

    #[embeddable_as(GuardianManagerImpl)]
    impl GuardianManager<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>, +IEmitArgentAccountEvent<TContractState>,
    > of IGuardianManager<ComponentState<TContractState>> {
        fn get_guardians_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.guardians_storage.get_all_hashes()
        }

        fn get_guardians_info(self: @ComponentState<TContractState>) -> Array<SignerInfo> {
            self.guardians_storage.get_all().span().to_signer_info()
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

        fn get_single_guardian(self: @ComponentState<TContractState>) -> Option<SignerStorageValue> {
            self.guardians_storage.single()
        }

        fn get_single_stark_guardian_pubkey(self: @ComponentState<TContractState>) -> Option<felt252> {
            self.get_single_guardian()?.starknet_pubkey_or_none()
        }

        fn change_guardians(
            ref self: ComponentState<TContractState>,
            guardian_guids_to_remove: Array<felt252>,
            guardians_to_add: Array<Signer>,
        ) {
            let mut guardians_to_add_storage = array![];
            for guardian in guardians_to_add {
                let guardian_storage = guardian.storage_value();
                self
                    .emit_signer_linked_event(
                        SignerLinked { signer_guid: guardian_storage.into_guid(), signer: guardian },
                    );
                guardians_to_add_storage.append(guardian_storage);
            };
            self.change_guardians_using_storage(guardian_guids_to_remove, guardians_to_add_storage);
        }

        fn complete_guardian_escape(
            ref self: ComponentState<TContractState>, new_guardian: Option<SignerStorageValue>,
        ) {
            if let Option::Some(new_guardian) = new_guardian {
                let new_guardian_guid = new_guardian.into_guid();
                let mut guardian_guids_to_remove = array![];
                for guardian_to_remove_guid in self.guardians_storage.get_all_hashes() {
                    if guardian_to_remove_guid != new_guardian_guid {
                        guardian_guids_to_remove.append(guardian_to_remove_guid);
                    };
                };
                self.change_guardians_using_storage(:guardian_guids_to_remove, guardians_to_add: array![new_guardian]);
            } else {
                self
                    .change_guardians_using_storage(
                        guardian_guids_to_remove: self.guardians_storage.get_all_hashes(), guardians_to_add: array![],
                    );
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
        /// @dev it will revert if there's any overlap between the guardians to add and the guardians to remove
        /// @dev it will revert if there are duplicate in the guardians to add or remove
        fn change_guardians_using_storage(
            ref self: ComponentState<TContractState>,
            guardian_guids_to_remove: Array<felt252>,
            guardians_to_add: Array<SignerStorageValue>,
        ) {
            let guardian_to_remove_span = guardian_guids_to_remove.span();
            for guid_to_remove in guardian_guids_to_remove {
                self.guardians_storage.remove(guid_to_remove);
                self.emit_guardian_removed(guid_to_remove);
            };

            for guardian in guardians_to_add {
                assert(!guardian_to_remove_span.contains(guardian.into_guid()), 'argent/duplicated-guids');
                let guardian_guid = self.guardians_storage.insert(guardian);
                self.emit_guardian_added(guardian_guid);
            };

            self.assert_valid_storage();
        }

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
