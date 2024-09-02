use argent::signer::{
    signer_signature::{Signer, SignerTrait, SignerSignature, SignerStorageValue, SignerSignatureTrait, SignerSpanTrait},
};
#[starknet::interface]
trait IOwnerManager<TContractState> {
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
    fn initialize(ref self: TContractState, signers: Array<Signer>);
    fn assert_valid_signer_count(self: @TContractState, signers_len: usize);
    fn assert_valid_storage(self: @TContractState);
    fn get_single_stark_owner_pubkey(self: @TContractState) -> Option<felt252>;
    fn get_single_owner(self: @TContractState) -> Option<SignerStorageValue>;
}


/// Managing the list of owners of the account
#[starknet::component]
mod owner_manager_component {
    use super::{IOwnerManager, IOwnerManagerInternal};
    use super::super::account_interface::SignerLinked;

    use argent::signer::{
        signer_signature::{Signer, SignerTrait, SignerSignature, SignerSignatureTrait, SignerSpanTrait, SignerStorageValue},
    };
    use argent::signer_storage::{
        signer_list::{
            signer_list_component::{OwnerAddedGuid, OwnerRemovedGuid}
        }
    };
    use argent::utils::{
        transaction_version::is_estimate_transaction,
        asserts::assert_only_self
    };

    /// Too many owners could make the account unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    struct Storage {
        // signerStorage : Vec<SignerStorageValue>
    } 

    #[embeddable_as(OwnerManagerImpl)]
    impl OwnerManager<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>
    > of IOwnerManager<ComponentState<TContractState>> {

        fn add_owners(ref self: ComponentState<TContractState>, owners_to_add: Array<Signer>) {
            assert_only_self();
            // let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);

            // let (signers_len, last_signer_guid) = signer_list_comp.load();

            // let new_signer_count = signers_len + signers_to_add.len();
            // self.assert_valid_signer_count(new_signer_count);

            // let mut guids = signers_to_add.span().to_guid_list();
            // signer_list_comp.add_signers(guids.span(), last_signer: last_signer_guid);
            // let mut signers_to_add_span = signers_to_add.span();
            // while let Option::Some(signer) = signers_to_add_span.pop_front() {
            //     let signer_guid = guids.pop_front().unwrap();
            //     signer_list_comp.emit(OwnerAddedGuid { new_owner_guid: signer_guid });
            //     signer_list_comp.emit(SignerLinked { signer_guid, signer: *signer });
            // };
        }

        fn remove_owners(
            ref self: ComponentState<TContractState>, owners_to_remove: Array<Signer>
        ) {
            assert_only_self();
            // let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            // let (signers_len, last_signer_guid) = signer_list_comp.load();

            // let new_signer_count = signers_len - signers_to_remove.len();
            // self.assert_valid_signer_count(new_signer_count);

            // let mut guids = signers_to_remove.span().to_guid_list();
            // signer_list_comp.remove_signers(guids.span(), last_signer: last_signer_guid);
            // while let Option::Some(removed_owner_guid) = guids.pop_front() {
            //     signer_list_comp.emit(OwnerRemovedGuid { removed_owner_guid })
            // };

        }

        fn replace_owner(ref self: ComponentState<TContractState>, owner_to_remove: Signer, owner_to_add: Signer) {
            assert_only_self();
            // let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            // let (_, last_signer) = signer_list_comp.load();

            // let signer_to_remove_guid = signer_to_remove.into_guid();
            // let signer_to_add_guid = signer_to_add.into_guid();
            // signer_list_comp.replace_signer(signer_to_remove_guid, signer_to_add_guid, last_signer);

            // signer_list_comp.emit(OwnerRemovedGuid { removed_owner_guid: signer_to_remove_guid });
            // signer_list_comp.emit(OwnerAddedGuid { new_owner_guid: signer_to_add_guid });
            // signer_list_comp.emit(SignerLinked { signer_guid: signer_to_add_guid, signer: signer_to_add });
        }

        fn get_owner_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            array![]
            // self.get_contract().get_signers()
        }

        fn is_owner(self: @ComponentState<TContractState>, owner: Signer) -> bool {
            false
            // self.get_contract().is_signer_in_list(signer.into_guid())
        }

        fn is_owner_guid(self: @ComponentState<TContractState>, owner_guid: felt252) -> bool {
            false
            // self.get_contract().is_signer_in_list(signer_guid)
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
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>
    > of IOwnerManagerInternal<ComponentState<TContractState>> {
        fn initialize(ref self: ComponentState<TContractState>, mut signers: Array<Signer>) {
            self.assert_valid_signer_count(signers.len());

            let mut guids = signers.span().to_guid_list();
            // assert_sorted_guids(guids.span());
            // signer_list_comp.add_signers(guids.span(), last_signer: 0);

            // while let Option::Some(signer) = signers.pop_front() {
            //     let signer_guid = guids.pop_front().unwrap();
            //     signer_list_comp.emit(OwnerAddedGuid { new_owner_guid: signer_guid });
            //     signer_list_comp.emit(SignerLinked { signer_guid, signer });
            // };
        }

        fn assert_valid_signer_count(
            self: @ComponentState<TContractState>, signers_len: usize
        ) {
            assert(signers_len != 0, 'argent/invalid-signers-len');
            assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        }

        fn assert_valid_storage(self: @ComponentState<TContractState>) {
            // self.assert_valid_signer_count(self.get_contract().get_signers_len());
        }

        fn get_single_owner(self: @ComponentState<TContractState>) -> Option<SignerStorageValue> {
            Option::None
        }

        fn get_single_stark_owner_pubkey(self: @ComponentState<TContractState>) -> Option<felt252> {
            Option::None
        }
    }
}
