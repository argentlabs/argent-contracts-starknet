#[starknet::contract]
mod ThresholdRecoveryMock {
    use argent::multisig::multisig::multisig_component;
    use argent::recovery::{threshold_recovery::threshold_recovery_component};
    use argent::signer_storage::signer_list::signer_list_component;

    component!(path: threshold_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ThresholdRecovery = threshold_recovery_component::ThresholdRecoveryImpl<ContractState>;
    #[abi(embed_v0)]
    impl ToggleThresholdRecovery =
        threshold_recovery_component::ToggleThresholdRecoveryImpl<ContractState>;
    impl ThresholdRecoveryInternal = threshold_recovery_component::ThresholdRecoveryInternalImpl<ContractState>;

    component!(path: multisig_component, storage: multisig, event: MultisigEvents);
    #[abi(embed_v0)]
    impl Multisig = multisig_component::MultisigImpl<ContractState>;
    #[abi(embed_v0)]
    impl MultisigInternal = multisig_component::MultisigInternalImpl<ContractState>;

    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    impl SignerListInternal = signer_list_component::SignerListInternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_list: signer_list_component::Storage,
        #[substorage(v0)]
        multisig: multisig_component::Storage,
        #[substorage(v0)]
        escape: threshold_recovery_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SignerListEvents: signer_list_component::Event,
        MultisigEvents: multisig_component::Event,
        EscapeEvents: threshold_recovery_component::Event,
    }
}

#[starknet::contract]
mod ExternalRecoveryMock {
    use argent::multisig::multisig::multisig_component;
    use argent::recovery::{external_recovery::external_recovery_component};
    use argent::signer_storage::signer_list::signer_list_component;

    component!(path: external_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ExternalRecovery = external_recovery_component::ExternalRecoveryImpl<ContractState>;
    #[abi(embed_v0)]
    impl ToggleExternalRecovery =
        external_recovery_component::ToggleExternalRecoveryImpl<ContractState>;

    component!(path: multisig_component, storage: multisig, event: MultisigEvents);
    #[abi(embed_v0)]
    impl Multisig = multisig_component::MultisigImpl<ContractState>;
    #[abi(embed_v0)]
    impl MultisigInternal = multisig_component::MultisigInternalImpl<ContractState>;

    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    impl SignerListInternal = signer_list_component::SignerListInternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_list: signer_list_component::Storage,
        #[substorage(v0)]
        multisig: multisig_component::Storage,
        #[substorage(v0)]
        escape: external_recovery_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SignerListEvents: signer_list_component::Event,
        MultisigEvents: multisig_component::Event,
        EscapeEvents: external_recovery_component::Event,
    }
}
