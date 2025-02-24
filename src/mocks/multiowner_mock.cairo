/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes.
/// Please refrain from relying on the functionality of this contract for any production code. 🚨
#[starknet::contract]
mod MultiownerMock {
    use argent::multiowner_account::argent_account::IEmitArgentAccountEvent;
    use argent::multiowner_account::argent_account::{ArgentAccount::Event as ArgentAccountEvent};
    use argent::multiowner_account::events::SignerLinked;
    use argent::multiowner_account::owner_manager::{
        owner_manager_component, owner_manager_component::OwnerManagerInternalImpl,
    };

    // Owner management
    component!(path: owner_manager_component, storage: owner_manager, event: OwnerManagerEvents);
    #[abi(embed_v0)]
    impl OwnerManager = owner_manager_component::OwnerManagerImpl<ContractState>;

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
        SignerLinked: SignerLinked,
    }

    // Required Callbacks
    impl OwnerManagerCallbackImpl of IEmitArgentAccountEvent<ContractState> {
        fn emit_event_callback(
            ref self: ContractState, event: ArgentAccountEvent,
        ) { // Cannot emit as the event is from another contract
        // It doesn't know how to translate the event to the current contract
        // self.emit(event);
        }
    }
}
