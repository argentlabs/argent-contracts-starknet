/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live environment. It is solely for testing, educational, or demonstration purposes. Any interactions with this contract will not have real-world consequences or effects on blockchain networks. Please refrain from relying on the functionality of this contract for any production. 🚨
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
        #[flat]
        SignerListEvents: signer_list_component::Event,
        #[flat]
        MultisigEvents: multisig_component::Event,
        #[flat]
        EscapeEvents: threshold_recovery_component::Event,
    }
}
#[starknet::contract]
mod ExternalRecoveryMock {
    use argent::external_recovery::{external_recovery::{external_recovery_component, IExternalRecoveryCallback}};
    use argent::multisig::multisig::multisig_component;
    use argent::signer_storage::signer_list::signer_list_component;
    use argent::utils::calls::execute_multicall;
    component!(path: external_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ExternalRecovery = external_recovery_component::ExternalRecoveryImpl<ContractState>;

    component!(path: multisig_component, storage: multisig, event: MultisigEvents);
    #[abi(embed_v0)]
    impl Multisig = multisig_component::MultisigImpl<ContractState>;
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
        #[flat]
        SignerListEvents: signer_list_component::Event,
        #[flat]
        MultisigEvents: multisig_component::Event,
        #[flat]
        EscapeEvents: external_recovery_component::Event,
    }

    impl IExternalRecoveryCallbackImpl of IExternalRecoveryCallback<ContractState> {
        fn execute_recovery_call(ref self: ContractState, selector: felt252, calldata: Span<felt252>) {
            execute_multicall(
                array![starknet::account::Call { to: starknet::get_contract_address(), selector, calldata }].span()
            );
        }
    }
}

