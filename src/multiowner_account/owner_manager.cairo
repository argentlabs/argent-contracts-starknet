use argent::signer::{
    signer_signature::{
        Signer, SignerTrait, SignerSignature, SignerStorageValue, SignerStorageTrait, SignerSignatureTrait,
        SignerSpanTrait
    },
};
use super::linked_set::SetItem;


impl SignerStorageValueSetItem of SetItem<SignerStorageValue> {
    fn is_valid_item(self: @SignerStorageValue) -> bool {
        *self.stored_value != 0
    }

    fn id(self: @SignerStorageValue) -> felt252 {
        (*self).into_guid()
    }
}

#[starknet::interface]
pub trait IOwnerManager<TContractState> {
    /// @notice Adds new owners to the account
    /// @dev will revert when trying to add a signer is already an owner
    /// @param owners_to_add An array with all the signers to add
    fn add_owners(ref self: TContractState, owners_to_add: Array<Signer>);

    /// @notice Removes owners
    /// @dev Will revert if any of the signers is not an owner
    /// @param owners_to_remove All the signers to remove
    fn remove_owners(ref self: TContractState, owners_to_remove: Array<Signer>);

    /// @notice Replace one owner with a different one
    /// @dev Will revert when trying to remove a signer that's not an owner
    /// @dev Will revert when trying to add a signer that's already an owner
    /// @param owner_to_remove Owner to remove
    /// @param owner_to_add Owner to add
    fn replace_owner(ref self: TContractState, owner_to_remove: Signer, owner_to_add: Signer);

    /// @notice Returns the guid of all the owners
    #[must_use]
    fn get_owner_guids(self: @TContractState) -> Array<felt252>;
    #[must_use]
    fn is_owner(self: @TContractState, owner: Signer) -> bool;
    #[must_use]
    fn is_owner_guid(self: @TContractState, owner_guid: felt252) -> bool;

    /// @notice Verifies whether a provided signature is valid and comes from one of the owners.
    /// @param hash Hash of the message being signed
    /// @param owner_signature Signature to be verified
    #[must_use]
    fn is_valid_owner_signature(self: @TContractState, hash: felt252, owner_signature: SignerSignature) -> bool;
}

#[starknet::interface]
trait IOwnerManagerInternal<TContractState> {
    fn initialize(ref self: TContractState, owners: Array<Signer>);
    fn assert_valid_storage(self: @TContractState);
    fn get_single_stark_owner_pubkey(self: @TContractState) -> Option<felt252>;
    fn get_single_owner(self: @TContractState) -> Option<SignerStorageValue>;
}

/// Managing the list of owners of the account
#[starknet::component]
mod owner_manager_component {
    use argent::signer::{
        signer_signature::{
            Signer, SignerTrait, SignerSignature, SignerSignatureTrait, SignerSpanTrait, SignerStorageValue,
            SignerStorageTrait
        },
    };
    use argent::signer_storage::{signer_list::{signer_list_component::{OwnerAddedGuid, OwnerRemovedGuid}}};
    use argent::utils::{transaction_version::is_estimate_transaction, asserts::assert_only_self};
    use starknet::storage::{
        Vec, StoragePointerReadAccess, StoragePointerWriteAccess, MutableVecTrait, StoragePathEntry, Map
    };
    use super::SignerStorageValueSetItem;

    use super::super::account_interface::SignerLinked;
    use super::super::linked_set::{
        LinkedSetMut, LinkedSetTraitMut, LinkedSetMutImpl, LinkedSet, LinkedSetTrait, LinkedSetImpl
    };
    use super::{IOwnerManager, IOwnerManagerInternal};

    /// Too many owners could make the account unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    struct Storage {
        owners_storage: Map<felt252, SignerStorageValue>
    }

    #[embeddable_as(OwnerManagerImpl)]
    impl OwnerManager<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of IOwnerManager<ComponentState<TContractState>> {
        fn add_owners(ref self: ComponentState<TContractState>, owners_to_add: Array<Signer>) {
            assert_only_self();
            let new_owner_count = self.owners_storage().len() + owners_to_add.len();
            self.assert_valid_owner_count(new_owner_count);

            for owner in owners_to_add {
                let signer_storage = owner.storage_value();
                // let guid  = signer_storage.into_guid();
                self.owners_storage_mut().add_item(signer_storage);
                // signer_list_comp.emit(OwnerAddedGuid { new_owner_guid: guid });
            // signer_list_comp.emit(SignerLinked { signer_guid, signer });
            };
        }

        fn remove_owners(ref self: ComponentState<TContractState>, owners_to_remove: Array<Signer>) {
            assert_only_self();

            let new_owner_count = self.owners_storage().len() - owners_to_remove.len();
            self.assert_valid_owner_count(new_owner_count);

            for owner in owners_to_remove {
                let guid = owner.into_guid();
                self.owners_storage_mut().remove(guid);
                //     signer_list_comp.emit(OwnerRemovedGuid { guid })
            };
        }

        fn replace_owner(ref self: ComponentState<TContractState>, owner_to_remove: Signer, owner_to_add: Signer) {
            assert_only_self();
            self.owners_storage_mut().remove(owner_to_remove.into_guid());
            self.owners_storage_mut().add_item(owner_to_add.storage_value());
            // signer_list_comp.emit(OwnerRemovedGuid { removed_owner_guid: signer_to_remove_guid });
        // signer_list_comp.emit(OwnerAddedGuid { new_owner_guid: signer_to_add_guid });
        // signer_list_comp.emit(SignerLinked { signer_guid: signer_to_add_guid, signer: signer_to_add });
        }

        fn get_owner_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.owners_storage().get_all_ids()
        }

        fn is_owner(self: @ComponentState<TContractState>, owner: Signer) -> bool {
            self.owners_storage().is_in_id(owner.into_guid())
        }

        fn is_owner_guid(self: @ComponentState<TContractState>, owner_guid: felt252) -> bool {
            self.owners_storage().is_in_id(owner_guid)
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
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>
    > of IOwnerManagerInternal<ComponentState<TContractState>> {
        fn initialize(ref self: ComponentState<TContractState>, mut owners: Array<Signer>) {
            self.assert_valid_owner_count(owners.len());
            // let mut last_guid: u256 = 0;
            for owner in owners {
                let signer_storage: SignerStorageValue = owner.storage_value();
                // let guid  = signer_storage.into_guid();
                // let guid_u256 : u256 = guid.into();
                // assert(guid_u256 > last_guid, 'argent/invalid-signers-order');
                self.owners_storage_mut().add_item(signer_storage);
                // signer_list_comp.emit(OwnerAddedGuid { new_owner_guid: guid });
            // signer_list_comp.emit(SignerLinked { signer_guid, signer });
            };
        }

        fn assert_valid_storage(self: @ComponentState<TContractState>) {
            self.assert_valid_owner_count(self.owners_storage().len());
        }

        fn get_single_owner(self: @ComponentState<TContractState>) -> Option<SignerStorageValue> {
            self.owners_storage().first()
        }

        fn get_single_stark_owner_pubkey(self: @ComponentState<TContractState>) -> Option<felt252> {
            self.get_single_owner()?.starknet_pubkey_or_none()
        }
    }

    #[generate_trait]
    impl Private<TContractState, +HasComponent<TContractState>> of PrivateTrait<TContractState> {
        fn owners_storage_mut(ref self: ComponentState<TContractState>) -> LinkedSetMut<SignerStorageValue> {
            LinkedSetMut { storage: self.owners_storage }
        }
        fn owners_storage(self: @ComponentState<TContractState>) -> LinkedSet<SignerStorageValue> {
            LinkedSet { storage: self.owners_storage }
        }
        fn assert_valid_owner_count(self: @ComponentState<TContractState>, signers_len: usize) {
            assert(signers_len != 0, 'argent/invalid-signers-len');
            assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        }
    }
}
