use argent::signer::signer_signature::{Signer, SignerInfo, SignerSignature, SignerStorageValue};

#[starknet::interface]
pub trait IOwnerManager<TContractState> {
    /// @notice Returns the guid of all the owners
    fn get_owner_guids(self: @TContractState) -> Array<felt252>;
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
    /// @notice Adds new owners to the account
    /// @dev will revert when trying to add a signer is already an owner
    /// @param owners_to_add An array with all the signers to add
    fn add_owners(ref self: TContractState, owners_to_add: Array<Signer>);

    /// @notice Removes owners
    /// @dev Will revert if any of the signers is not an owner
    /// @param owners_to_remove All the signers to remove
    fn remove_owners(ref self: TContractState, owner_guids_to_remove: Array<felt252>);
    fn reset_owners(ref self: TContractState, new_single_owner: SignerStorageValue);
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
        SignerStorageValue, SignerTrait,
    };
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
        fn get_owner_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
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

        fn add_owners(ref self: ComponentState<TContractState>, owners_to_add: Array<Signer>) {
            let owner_len = self.owners_storage.len();

            self.assert_valid_owner_count(owner_len + owners_to_add.len());
            for owner in owners_to_add {
                let owner_guid = self.owners_storage.insert(owner.storage_value());
                self.emit_owner_added(owner_guid);
                self.emit_signer_linked_event(SignerLinked { signer_guid: owner_guid, signer: owner });
            };
        }

        fn remove_owners(ref self: ComponentState<TContractState>, owner_guids_to_remove: Array<felt252>) {
            self.assert_valid_owner_count(self.owners_storage.len() - owner_guids_to_remove.len());

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

        fn reset_owners(ref self: ComponentState<TContractState>, new_single_owner: SignerStorageValue) {
            let new_single_owner_guid = new_single_owner.into_guid();

            let mut new_owner_was_already_owner = false;
            let current_owner_guids = self.owners_storage.get_all_hashes();
            for current_owner_guid in current_owner_guids {
                if current_owner_guid != new_single_owner_guid {
                    self.owners_storage.remove(current_owner_guid);
                    self.emit_owner_removed(current_owner_guid);
                } else {
                    new_owner_was_already_owner = true;
                }
            };
            if !new_owner_was_already_owner {
                self.owners_storage.insert(new_single_owner);
                self.emit_owner_added(new_single_owner_guid);
            }
        }
    }

    #[generate_trait]
    impl Private<
        TContractState, +HasComponent<TContractState>, +IEmitArgentAccountEvent<TContractState>, +Drop<TContractState>,
    > of PrivateTrait<TContractState> {
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
