/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes. Any interactions with this contract
/// will not have real-world consequences or effects on blockchain networks. Please refrain from relying on the
/// functionality of this contract for any production. 🚨
#[starknet::contract]
mod ExternalRecoveryMock {
    use argent::multisig_account::external_recovery::{
        external_recovery::{external_recovery_component, IExternalRecoveryCallback}
    };
    use argent::multisig_account::signer_manager::signer_manager::signer_manager_component;
    use argent::multisig_account::signer_storage::signer_list::signer_list_component;
    use argent::utils::calls::execute_multicall;
    use openzeppelin_security::reentrancyguard::ReentrancyGuardComponent;
    component!(path: external_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ExternalRecovery = external_recovery_component::ExternalRecoveryImpl<ContractState>;

    // Signer management
    component!(path: signer_manager_component, storage: signer_manager, event: SignerManagerEvents);
    #[abi(embed_v0)]
    impl SignerManager = signer_manager_component::SignerManagerImpl<ContractState>;
    impl SignerManagerInternal = signer_manager_component::SignerManagerInternalImpl<ContractState>;

    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    impl SignerListInternal = signer_list_component::SignerListInternalImpl<ContractState>;

    // Reentrancy guard
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_list: signer_list_component::Storage,
        #[substorage(v0)]
        signer_manager: signer_manager_component::Storage,
        #[substorage(v0)]
        escape: external_recovery_component::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SignerListEvents: signer_list_component::Event,
        #[flat]
        SignerManagerEvents: signer_manager_component::Event,
        #[flat]
        EscapeEvents: external_recovery_component::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
    }

    impl IExternalRecoveryCallbackImpl of IExternalRecoveryCallback<ContractState> {
        fn execute_recovery_call(ref self: ContractState, selector: felt252, calldata: Span<felt252>) {
            execute_multicall(
                array![starknet::account::Call { to: starknet::get_contract_address(), selector, calldata }].span()
            );
        }
    }
}

