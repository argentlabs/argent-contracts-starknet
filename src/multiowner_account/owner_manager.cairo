use argent::signer::signer_signature::{Signer, SignerInfo, SignerSignature, SignerStorageValue, SignerType};

#[starknet::interface]
pub trait IOwnerManager<TContractState> {
    /// @notice Returns the public key if the requested role is Starknet, Eip191 or Secp256k1 and panic for other types
    /// @dev Fails if there is more than one owner
    fn get_owner(self: @TContractState) -> felt252;
    fn get_owner_type(self: @TContractState) -> SignerType;
    fn get_owner_guid(self: @TContractState) -> felt252;

    /// @notice Returns the guid of all the owners
    fn get_owners_guids(self: @TContractState) -> Array<felt252>;
    fn get_owners_info(self: @TContractState) -> Array<SignerInfo>;
    fn is_owner(self: @TContractState, owner: Signer) -> bool;
    fn is_owner_guid(self: @TContractState, owner_guid: felt252) -> bool;

    /// @notice Verifies whether a provided signature is valid and comes from one of the owners.
    /// @param hash Hash of the message being signed
    /// @param owner_signature Signature to be verified
    #[must_use]
    fn is_valid_owner_signature(self: @TContractState, hash: felt252, owner_signature: SignerSignature) -> bool;
}

trait IOwnerManagerInternal<TContractState> {
    /// @notice Initializes the contract with the first owner. Should ony be called in the constructor
    /// @param owner The first owner of the account
    /// @return The guid of the owner
    fn initialize(ref self: TContractState, owner: Signer) -> felt252;
    fn initialize_from_upgrade(ref self: TContractState, signer_storage: SignerStorageValue);
    fn change_owners(ref self: TContractState, owner_guids_to_remove: Array<felt252>, owners_to_add: Array<Signer>);
    fn complete_owner_escape(ref self: TContractState, new_owner: SignerStorageValue);
    fn assert_valid_storage(self: @TContractState);
    fn get_single_stark_owner_pubkey(self: @TContractState) -> Option<felt252>;
    fn get_single_owner(self: @TContractState) -> Option<SignerStorageValue>;
}

/// Managing the list of owners of the account
#[starknet::component]
mod owner_manager_component {
    use argent::account::interface::IEmitArgentAccountEvent;
    use argent::multiowner_account::argent_account::ArgentAccount::Event as ArgentAccountEvent;
    use argent::multiowner_account::events::{OwnerAddedGuid, OwnerRemovedGuid, SignerLinked};
    use argent::multiowner_account::signer_storage_linked_set::SignerStorageValueLinkedSetConfig;
    use argent::signer::signer_signature::{
        Signer, SignerInfo, SignerSignature, SignerSignatureTrait, SignerSpanTrait, SignerStorageTrait,
        SignerStorageValue, SignerTrait, SignerType,
    };
    use argent::utils::array_ext::SpanContains;
    use argent::utils::linked_set_with_head::{
        LinkedSetWithHead, LinkedSetWithHeadReadImpl, LinkedSetWithHeadWriteImpl, MutableLinkedSetWithHeadReadImpl,
    };
    use argent::utils::{asserts::assert_only_self, transaction_version::is_estimate_transaction};
    use super::{IOwnerManager, IOwnerManagerInternal};

    /// Too many owners could make the account unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    struct Storage {
        owners_storage: LinkedSetWithHead<SignerStorageValue>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnerAddedGuid: OwnerAddedGuid,
        OwnerRemovedGuid: OwnerRemovedGuid,
    }

    #[embeddable_as(OwnerManagerImpl)]
    impl OwnerManager<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>, +IEmitArgentAccountEvent<TContractState>,
    > of IOwnerManager<ComponentState<TContractState>> {
        fn get_owner(self: @ComponentState<TContractState>) -> felt252 {
            let owner = self.get_single_owner().expect('argent/no-single-owner');
            assert(!owner.is_stored_as_guid(), 'argent/only_guid');
            owner.stored_value
        }

        fn get_owner_type(self: @ComponentState<TContractState>) -> SignerType {
            self.get_single_owner().expect('argent/no-single-owner').signer_type
        }

        fn get_owner_guid(self: @ComponentState<TContractState>) -> felt252 {
            self.get_single_owner().expect('argent/no-single-owner').into_guid()
        }

        fn get_owners_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.owners_storage.get_all_hashes()
        }

        fn get_owners_info(self: @ComponentState<TContractState>) -> Array<SignerInfo> {
            self.owners_storage.get_all().span().to_signer_info()
        }

        #[inline(always)]
        fn is_owner(self: @ComponentState<TContractState>, owner: Signer) -> bool {
            self.owners_storage.contains(owner.storage_value())
        }

        #[inline(always)]
        fn is_owner_guid(self: @ComponentState<TContractState>, owner_guid: felt252) -> bool {
            self.owners_storage.contains_by_hash(owner_guid)
        }

        #[must_use]
        fn is_valid_owner_signature(
            self: @ComponentState<TContractState>, hash: felt252, owner_signature: SignerSignature,
        ) -> bool {
            if !self.is_owner(owner_signature.signer()) {
                return false;
            }
            return owner_signature.is_valid_signature(hash) || is_estimate_transaction();
        }
    }

    impl OwnerManagerInternalImpl<
        TContractState, +HasComponent<TContractState>, +IEmitArgentAccountEvent<TContractState>, +Drop<TContractState>,
    > of IOwnerManagerInternal<ComponentState<TContractState>> {
        fn initialize(ref self: ComponentState<TContractState>, owner: Signer) -> felt252 {
            let guid = self.owners_storage.insert(owner.storage_value());
            self.emit_signer_linked_event(SignerLinked { signer_guid: guid, signer: owner });
            self.emit_owner_added(guid);
            guid
        }

        fn initialize_from_upgrade(ref self: ComponentState<TContractState>, signer_storage: SignerStorageValue) {
            // Sanity check
            assert(self.owners_storage.len() == 0, 'argent/already-initialized');
            let guid = self.owners_storage.insert(signer_storage);
            // SignerLinked event is not needed here but OwnerAddedGuid is needed
            self.emit_owner_added(guid);
        }

        fn assert_valid_storage(self: @ComponentState<TContractState>) {
            self.assert_valid_owner_count(self.owners_storage.len());
        }

        fn get_single_owner(self: @ComponentState<TContractState>) -> Option<SignerStorageValue> {
            self.owners_storage.single()
        }

        fn get_single_stark_owner_pubkey(self: @ComponentState<TContractState>) -> Option<felt252> {
            self.get_single_owner()?.starknet_pubkey_or_none()
        }

        fn change_owners(
            ref self: ComponentState<TContractState>,
            owner_guids_to_remove: Array<felt252>,
            owners_to_add: Array<Signer>,
        ) {
            let mut owners_to_add_storage = array![];
            for owner in owners_to_add {
                let owner_storage = owner.storage_value();
                self.emit_signer_linked_event(SignerLinked { signer_guid: owner_storage.into_guid(), signer: owner });
                owners_to_add_storage.append(owner_storage);
            };
            self.change_owners_using_storage(owner_guids_to_remove, owners_to_add_storage);
        }

        fn complete_owner_escape(ref self: ComponentState<TContractState>, new_owner: SignerStorageValue) {
            let new_owner_guid = new_owner.into_guid();
            let mut owner_guids_to_remove = array![];
            for owner_to_remove_guid in self.owners_storage.get_all_hashes() {
                if owner_to_remove_guid != new_owner_guid {
                    owner_guids_to_remove.append(owner_to_remove_guid);
                };
            };

            self.change_owners_using_storage(:owner_guids_to_remove, owners_to_add: array![new_owner]);
        }
    }

    #[generate_trait]
    impl Private<
        TContractState, +HasComponent<TContractState>, +IEmitArgentAccountEvent<TContractState>, +Drop<TContractState>,
    > of PrivateTrait<TContractState> {
        /// @dev it will revert if there's any overlap between the owners to add and the owners to remove
        /// @dev it will revert if there are duplicate in the owners to add or remove
        fn change_owners_using_storage(
            ref self: ComponentState<TContractState>,
            owner_guids_to_remove: Array<felt252>,
            owners_to_add: Array<SignerStorageValue>,
        ) {
            let owner_guids_to_remove_span = owner_guids_to_remove.span();
            for guid_to_remove in owner_guids_to_remove {
                self.owners_storage.remove(guid_to_remove);
                self.emit_owner_removed(guid_to_remove);
            };

            for owner_to_add in owners_to_add {
                assert(!owner_guids_to_remove_span.contains(owner_to_add.into_guid()), 'argent/duplicated-guids');
                let owner_guid = self.owners_storage.insert(owner_to_add);
                self.emit_owner_added(owner_guid);
            };

            self.assert_valid_storage();
        }

        fn assert_valid_owner_count(self: @ComponentState<TContractState>, signers_len: usize) {
            assert(signers_len != 0, 'argent/invalid-signers-len');
            assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        }

        fn emit_signer_linked_event(ref self: ComponentState<TContractState>, event: SignerLinked) {
            let mut contract = self.get_contract_mut();
            contract.emit_event_callback(ArgentAccountEvent::SignerLinked(event));
        }

        fn emit_owner_added(ref self: ComponentState<TContractState>, new_owner_guid: felt252) {
            self.emit(OwnerAddedGuid { new_owner_guid });
        }

        fn emit_owner_removed(ref self: ComponentState<TContractState>, removed_owner_guid: felt252) {
            self.emit(OwnerRemovedGuid { removed_owner_guid });
        }
    }
}
