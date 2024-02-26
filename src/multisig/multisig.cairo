/// @notice Implements the methods of a multisig such as 
/// adding or removing signers, changing the threshold, etc
#[starknet::component]
mod multisig_component {
    use argent::multisig::interface::{IArgentMultisig, IArgentMultisigInternal};
    use argent::signer::{signer_signature::{Signer, IntoGuid, SignerSignature, SignerSignatureTrait},};
    use argent::signer_storage::{
        interface::ISignerList,
        signer_list::{
            signer_list_component,
            signer_list_component::{OwnerAdded, OwnerRemoved, SignerLinked, SignerListInternalImpl}
        }
    };
    use argent::utils::{
        asserts::{assert_only_self},
        transaction_version::{
            assert_correct_invoke_version, assert_no_unsupported_v3_fields, assert_correct_deploy_account_version
        },
        serialization::full_deserialize,
    };
    use core::array::ArrayTrait;
    use core::result::ResultTrait;
    use starknet::{get_tx_info, get_contract_address, VALIDATED, ClassHash, account::Call};

    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    #[storage]
    struct Storage {
        threshold: usize,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ThresholdUpdated: ThresholdUpdated
    }

    /// @notice Emitted when the multisig threshold changes
    /// @param new_threshold New threshold
    #[derive(Drop, starknet::Event)]
    struct ThresholdUpdated {
        new_threshold: usize,
    }

    #[embeddable_as(MultisigImpl)]
    impl MultiSig<
        TContractState,
        +HasComponent<TContractState>,
        impl SignerList: signer_list_component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IArgentMultisig<ComponentState<TContractState>> {
        fn change_threshold(ref self: ComponentState<TContractState>, new_threshold: usize) {
            assert_only_self();
            assert(new_threshold != self.threshold.read(), 'argent/same-threshold');
            let new_signers_count = self.get_contract().get_signers_len();

            self.assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);
            self.threshold.write(new_threshold);
            self.emit(ThresholdUpdated { new_threshold });
        }

        fn add_signers(ref self: ComponentState<TContractState>, new_threshold: usize, signers_to_add: Array<Signer>) {
            assert_only_self();
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);

            let (signers_len, last_signer_guid) = signer_list_comp.load();
            let previous_threshold = self.threshold.read();

            let new_signers_count = signers_len + signers_to_add.len();
            self.assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

            let mut signers_span = signers_to_add.span();
            let mut last_signer = last_signer_guid;
            loop {
                let signer = match signers_span.pop_front() {
                    Option::Some(signer) => (*signer),
                    Option::None => { break; }
                };
                let signer_guid = signer.into_guid().expect('argent/invalid-signer-guid');
                signer_list_comp.add_signer(signer_to_add: signer_guid, last_signer: last_signer);
                signer_list_comp.emit(OwnerAdded { new_owner_guid: signer_guid });
                signer_list_comp.emit(SignerLinked { signer_guid: signer_guid, signer: signer });
                last_signer = signer_guid;
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
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            let (signers_len, last_signer_guid) = signer_list_comp.load();
            let previous_threshold = self.threshold.read();

            let new_signers_count = signers_len - signers_to_remove.len();
            self.assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

            let mut signers_span = signers_to_remove.span();
            let mut last_signer = last_signer_guid;
            loop {
                let signer_guid = match signers_span.pop_front() {
                    Option::Some(signer) => (*signer).into_guid().expect('argent/invalid-signer-guid'),
                    Option::None => { break; }
                };
                last_signer = signer_list_comp.remove_signer(signer_to_remove: signer_guid, last_signer: last_signer);
                signer_list_comp.emit(OwnerRemoved { removed_owner_guid: signer_guid });
            };

            self.threshold.write(new_threshold);
            if previous_threshold != new_threshold {
                self.emit(ThresholdUpdated { new_threshold });
            }
        }

        fn reorder_signers(ref self: ComponentState<TContractState>, new_signer_order: Array<Signer>) {
            assert_only_self();
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            let (signers_len, mut last_signer) = signer_list_comp.load();
            assert(new_signer_order.len() == signers_len, 'argent/too-short');
            // remove all the signers of the list
            let mut new_signer_order_span = new_signer_order.span();
            let mut new_signer_order_guid = array![];
            loop {
                let signer_guid = match new_signer_order_span.pop_front() {
                    Option::Some(signer) => (*signer).into_guid().expect('argent/invalid-signer-guid'),
                    Option::None => { break; }
                };
                new_signer_order_guid.append(signer_guid);
                last_signer = signer_list_comp.remove_signer(signer_to_remove: signer_guid, last_signer: last_signer);
            };
            // add all the signers of the list
            signer_list_comp.add_signers(signers_to_add: new_signer_order_guid.span(), last_signer: 0);
        }

        fn replace_signer(ref self: ComponentState<TContractState>, signer_to_remove: Signer, signer_to_add: Signer) {
            assert_only_self();
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            let (_, last_signer) = signer_list_comp.load();

            let signer_to_remove_guid = signer_to_remove.into_guid().expect('argent/invalid-target-guid');
            let signer_to_add_guid = signer_to_add.into_guid().expect('argent/invalid-new-signer-guid');
            signer_list_comp.replace_signer(signer_to_remove_guid, signer_to_add_guid, last_signer);

            signer_list_comp.emit(OwnerRemoved { removed_owner_guid: signer_to_remove_guid });
            signer_list_comp.emit(OwnerAdded { new_owner_guid: signer_to_add_guid });
            signer_list_comp.emit(SignerLinked { signer_guid: signer_to_add_guid, signer: signer_to_add });
        }

        fn get_threshold(self: @ComponentState<TContractState>) -> usize {
            self.threshold.read()
        }

        fn get_signer_guids(self: @ComponentState<TContractState>) -> Array<felt252> {
            self.get_contract().get_signers()
        }

        fn is_signer(self: @ComponentState<TContractState>, signer: Signer) -> bool {
            self.get_contract().is_signer_in_list(signer.into_guid().expect('argent/invalid-signer-guid'))
        }

        fn is_signer_guid(self: @ComponentState<TContractState>, signer_guid: felt252) -> bool {
            self.get_contract().is_signer_in_list(signer_guid)
        }

        fn is_valid_signer_signature(
            self: @ComponentState<TContractState>, hash: felt252, signer_signature: SignerSignature
        ) -> bool {
            let is_signer = self
                .get_contract()
                .is_signer_in_list(signer_signature.signer_into_guid().expect('argent/invalid-signer-guid'));
            assert(is_signer, 'argent/not-a-signer');
            signer_signature.is_valid_signature(hash)
        }
    }

    #[embeddable_as(MultisigInternalImpl)]
    impl MultiSigInternal<
        TContractState,
        +HasComponent<TContractState>,
        impl SignerList: signer_list_component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IArgentMultisigInternal<ComponentState<TContractState>> {
        fn initialize(ref self: ComponentState<TContractState>, threshold: usize, signers: Array<Signer>) {
            assert(self.threshold.read() == 0, 'argent/already-initialized');

            let new_signers_count = signers.len();
            self.assert_valid_threshold_and_signers_count(threshold, new_signers_count);

            let mut signers_span = signers.span();
            let mut last_signer = 0;
            let mut signer_list_comp = get_dep_component_mut!(ref self, SignerList);
            loop {
                let signer = match signers_span.pop_front() {
                    Option::Some(signer) => (*signer),
                    Option::None => { break; }
                };
                let signer_guid = signer.into_guid().expect('argent/invalid-signer-guid');
                signer_list_comp.add_signer(signer_to_add: signer_guid, last_signer: last_signer);
                signer_list_comp.emit(OwnerAdded { new_owner_guid: signer_guid });
                signer_list_comp.emit(SignerLinked { signer_guid: signer_guid, signer: signer });
                last_signer = signer_guid;
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
            self.assert_valid_threshold_and_signers_count(self.threshold.read(), self.get_contract().get_signers_len());
        }
    }
}
