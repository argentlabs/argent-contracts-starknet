/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes. Any interactions with this contract
/// will not have real-world consequences or effects on blockchain networks. Please refrain from relying on the
/// functionality of this contract for any production. 🚨
#[starknet::contract]
mod MultiownerMock {
    use argent::multiowner_account::events::SignerLinked;
    use argent::multiowner_account::owner_manager::{IOwnerManager, IOwnerManagerCallback, owner_manager_component};

    // Owner management
    component!(path: owner_manager_component, storage: owner_manager, event: OwnerManagerEvents);

    #[abi(embed_v0)]
    impl OwnerManager = owner_manager_component::OwnerManagerImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnerManagerInternal = owner_manager_component::OwnerManagerInternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        owner_manager: owner_manager_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnerManagerEvents: owner_manager_component::Event,
        gnerLinked: SignerLinked,
    }

    // Required Callbacks
    impl OwnerManagerCallbackImpl of IOwnerManagerCallback<ContractState> {
        fn emit_signer_linked_event(ref self: ContractState, event: SignerLinked) {
            self.emit(event);
        }
    }
}
