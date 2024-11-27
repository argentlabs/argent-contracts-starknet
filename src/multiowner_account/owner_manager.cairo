use argent::multiowner_account::events::SignerLinked;
use argent::signer::signer_signature::{Signer, SignerSignature, SignerStorageValue, SignerStorageTrait};
use argent::utils::linked_set::SetItem;

impl SignerStorageValueSetItem of SetItem<SignerStorageValue> {
    fn is_valid_item(self: @SignerStorageValue) -> bool {
        *self.stored_value != 0
    }

    fn id(self: @SignerStorageValue) -> felt252 {
        (*self).into_guid()
    }
}

// TODO just have a generic emit_event?
trait IOwnerManagerCallback<TContractState> {
    fn emit_signer_linked_event(ref self: TContractState, event: SignerLinked);
}


#[starknet::interface]
pub trait IOwnerManager<TContractState> {
    /// @notice Returns the guid of all the owners
    fn get_owner_guids(self: @TContractState) -> Array<felt252>;
    fn is_owner(self: @TContractState, owner: Signer) -> bool;
    fn is_owner_guid(self: @TContractState, owner_guid: felt252) -> bool;

    /// @notice Verifies whether a provided signature is valid and comes from one of the owners.
    /// @param hash Hash of the message being signed
    /// @param owner_signature Signature to be verified
    #[must_use]
    fn is_valid_owner_signature(self: @TContractState, hash: felt252, owner_signature: SignerSignature) -> bool;
}

#[starknet::interface]
trait IOwnerManagerInternal<TContractState> {
    fn initialize(ref self: TContractState, owner: Signer);
    fn initialize_from_upgrade(ref self: TContractState, signer_storage: SignerStorageValue);
    /// @notice Adds new owners to the account
    /// @dev will revert when trying to add a signer is already an owner
    /// @param owners_to_add An array with all the signers to add
    fn add_owners(ref self: TContractState, owners_to_add: Array<Signer>);

    /// @notice Removes owners
    /// @dev Will revert if any of the signers is not an owner
    /// @param owners_to_remove All the signers to remove
    // TODO can't remove self or provide signature
    fn remove_owners(ref self: TContractState, owner_guids_to_remove: Array<felt252>);
    fn is_valid_owners_replacement(self: @TContractState, new_single_owner: Signer) -> bool;
    fn replace_all_owners_with_one(ref self: TContractState, new_single_owner: SignerStorageValue);
    fn assert_valid_storage(self: @TContractState);
    fn get_single_stark_owner_pubkey(self: @TContractState) -> Option<felt252>;
    fn get_single_owner(self: @TContractState) -> Option<SignerStorageValue>;
}

/// Managing the list of owners of the account
#[starknet::component]
mod owner_manager_component {
    use argent::multiowner_account::events::{SignerLinked, OwnerAddedGuid, OwnerRemovedGuid};
    use argent::signer::signer_signature::{
        Signer, SignerTrait, SignerSignature, SignerSignatureTrait, SignerSpanTrait, SignerStorageValue,
        SignerStorageTrait
    };
    use argent::utils::{
        linked_set::{LinkedSet, LinkedSetReadImpl, LinkedSetWriteImpl, MutableLinkedSetReadImpl},
        transaction_version::is_estimate_transaction
    };
    use super::{IOwnerManager, IOwnerManagerInternal, SignerStorageValueSetItem, IOwnerManagerCallback};
    /// Too many owners could make the account unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    struct Storage {
        owners_storage: LinkedSet<SignerStorageValue>
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnerAddedGuid: OwnerAddedGuid,
        OwnerRemovedGuid: OwnerRemovedGuid,
    }

    #[embeddable_as(OwnerManagerImpl)]
    impl OwnerManager<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>, +IOwnerManagerCallback<TContractState>
    > of IOwnerManager<ComponentState<TContractState>> {
        fn get_owner_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.owners_storage.get_all_ids()
        }

        fn is_owner(self: @ComponentState<TContractState>, owner: Signer) -> bool {
            self.owners_storage.is_in_id(owner.into_guid())
        }

        fn is_owner_guid(self: @ComponentState<TContractState>, owner_guid: felt252) -> bool {
            self.owners_storage.is_in_id(owner_guid)
        }

        #[must_use]
        fn is_valid_owner_signature(
            self: @ComponentState<TContractState>, hash: felt252, owner_signature: SignerSignature
        ) -> bool {
            if !self.is_owner(owner_signature.signer()) {
                return false;
            }
            return owner_signature.is_valid_signature(hash) || is_estimate_transaction();
        }
    }

    #[embeddable_as(OwnerManagerInternalImpl)]
    impl OwnerManagerInternal<
        TContractState, +HasComponent<TContractState>, +IOwnerManagerCallback<TContractState>, +Drop<TContractState>
    > of IOwnerManagerInternal<ComponentState<TContractState>> {
        fn initialize(ref self: ComponentState<TContractState>, owner: Signer) {
            // TODO later we probably want to optimize this function instead of just delegating to add_owners
            self.add_owners(array![owner]);
        }

        fn initialize_from_upgrade(ref self: ComponentState<TContractState>, signer_storage: SignerStorageValue) {
            // We don't want to emit any events in this case
            assert(self.owners_storage.len() == 0, 'argent/already-initialized');
            self.owners_storage.add_item(signer_storage);
        }

        fn add_owners(ref self: ComponentState<TContractState>, owners_to_add: Array<Signer>) {
            let new_owner_count = self.owners_storage.len() + owners_to_add.len();
            self.assert_valid_owner_count(new_owner_count);
            for owner in owners_to_add {
                let signer_storage = owner.storage_value();
                let guid = signer_storage.into_guid();
                // TODO optimize insertions
                self.owners_storage.add_item(signer_storage);
                self.emit_owner_added(guid);
                self.emit_signer_linked_event(SignerLinked { signer_guid: guid, signer: owner });
            };
        }

        fn remove_owners(ref self: ComponentState<TContractState>, owner_guids_to_remove: Array<felt252>) {
            // TODO assert account not bricked, specially if there's not guardian
            let new_owner_count = self.owners_storage.len() - owner_guids_to_remove.len();
            self.assert_valid_owner_count(new_owner_count);

            for guid in owner_guids_to_remove {
                self.owners_storage.remove(guid);
                self.emit_owner_removed(guid);
            };
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

        fn is_valid_owners_replacement(self: @ComponentState<TContractState>, new_single_owner: Signer) -> bool {
            !self.owners_storage.is_in_id(new_single_owner.into_guid())
        }

        fn replace_all_owners_with_one(ref self: ComponentState<TContractState>, new_single_owner: SignerStorageValue) {
            let new_owner_guid = new_single_owner.into_guid();
            let current_owners = self.owners_storage.get_all_ids();
            for current_owner_guid in current_owners {
                assert(current_owner_guid != new_owner_guid, 'argent/already-an-owner');
                self.owners_storage.remove(current_owner_guid);
                self.emit_owner_removed(current_owner_guid);
            };
            self.owners_storage.add_item(new_single_owner);
            self.emit_owner_added(new_owner_guid);
        }
    }

    #[generate_trait]
    impl Private<
        TContractState, +HasComponent<TContractState>, +IOwnerManagerCallback<TContractState>, +Drop<TContractState>
    > of PrivateTrait<TContractState> {
        fn assert_valid_owner_count(self: @ComponentState<TContractState>, signers_len: usize) {
            assert(signers_len != 0, 'argent/invalid-signers-len');
            assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        }
        fn emit_signer_linked_event(ref self: ComponentState<TContractState>, event: SignerLinked) {
            let mut contract = self.get_contract_mut();
            contract.emit_signer_linked_event(event);
        }
        fn emit_owner_added(ref self: ComponentState<TContractState>, new_owner_guid: felt252) {
            self.emit(OwnerAddedGuid { new_owner_guid });
        }
        fn emit_owner_removed(ref self: ComponentState<TContractState>, removed_owner_guid: felt252) {
            self.emit(OwnerRemovedGuid { removed_owner_guid });
        }
    }
}
