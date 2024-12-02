/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes.
/// Please refrain from relying on the functionality of this contract for any production code. 🚨
#[starknet::contract]
mod MultisigMock {
    use argent::multisig_account::signer_manager::signer_manager::signer_manager_component;

    component!(path: signer_manager_component, storage: signer_manager, event: SignerManagerEvents);
    #[abi(embed_v0)]
    impl SignerManager = signer_manager_component::SignerManagerImpl<ContractState>;
    impl SignerManagerInternal = signer_manager_component::SignerManagerInternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_manager: signer_manager_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SignerManagerEvents: signer_manager_component::Event,
    }
}
