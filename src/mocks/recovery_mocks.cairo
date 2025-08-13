/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes.
/// Please refrain from relying on the functionality of this contract for any production code. 🚨
#[starknet::contract]
mod ExternalRecoveryMock {
    use argent::multisig_account::external_recovery::{IExternalRecoveryCallback, external_recovery_component};
    use argent::multisig_account::signer_manager::{
        signer_manager_component, signer_manager_component::SignerManagerInternalImpl,
    };
    use argent::utils::calls::execute_multicall;
    use openzeppelin_security::reentrancyguard::{ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl};

    component!(path: external_recovery_component, storage: escape, event: EscapeEvents);
    #[abi(embed_v0)]
    impl ExternalRecovery = external_recovery_component::ExternalRecoveryImpl<ContractState>;

    // Signer management
    component!(path: signer_manager_component, storage: signer_manager, event: SignerManagerEvents);
    #[abi(embed_v0)]
    impl SignerManager = signer_manager_component::SignerManagerImpl<ContractState>;

    // Reentrancy guard
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);

    #[storage]
    struct Storage {
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
        SignerManagerEvents: signer_manager_component::Event,
        #[flat]
        EscapeEvents: external_recovery_component::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
    }

    impl IExternalRecoveryCallbackImpl of IExternalRecoveryCallback<ContractState> {
        fn execute_recovery_call(ref self: ContractState, selector: felt252, calldata: Span<felt252>) {
            execute_multicall(
                array![starknet::account::Call { to: starknet::get_contract_address(), selector, calldata }].span(),
            );
        }
    }
}

