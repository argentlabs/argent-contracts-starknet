/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes. Please refrain from relying on the
/// functionality of this contract for any production. 🚨

use starknet::ClassHash;

// Those functions are called when upgrading
#[starknet::interface]
trait IArgentAccountProfiler<TContractState> {
    fn upgrade(ref self: TContractState, new_implementation: ClassHash);
}


#[starknet::contract]
mod ArgentAccountProfile {
    use argent::multiowner_account::argent_account::ArgentAccount::Event as ArgentAccountEvent;
    use argent::multiowner_account::argent_account::IEmitArgentAccountEvent;
    use argent::multiowner_account::guardian_manager::{
        guardian_manager_component, guardian_manager_component::GuardianManagerInternal,
    };
    use argent::multiowner_account::owner_manager::{
        owner_manager_component, owner_manager_component::OwnerManagerInternalImpl,
    };
    use argent::signer::signer_signature::Signer;
    use starknet::{ClassHash, syscalls::replace_class_syscall};

    // Owner management
    component!(path: owner_manager_component, storage: owner_manager, event: OwnerManagerEvents);
    #[abi(embed_v0)]
    impl OwnerManager = owner_manager_component::OwnerManagerImpl<ContractState>;
    // Guardian management
    component!(path: guardian_manager_component, storage: guardian_manager, event: GuardianManagerEvents);
    #[abi(embed_v0)]
    impl GuardianManager = guardian_manager_component::GuardianManagerImpl<ContractState>;

    #[abi(embed_v0)]
    #[storage]
    struct Storage {
        #[substorage(v0)]
        owner_manager: owner_manager_component::Storage,
        #[substorage(v0)]
        guardian_manager: guardian_manager_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnerManagerEvents: owner_manager_component::Event,
        GuardianManagerEvents: guardian_manager_component::Event,
    }

    // Required Callbacks
    impl EmitArgentAccountEventImpl of IEmitArgentAccountEvent<ContractState> {
        fn emit_event_callback(ref self: ContractState, event: ArgentAccountEvent) {}
    }
    #[constructor]
    fn constructor(ref self: ContractState, owner: Signer, guardian: Option<Signer>) {
        self.owner_manager.initialize(owner);
        if let Option::Some(guardian) = guardian {
            self.guardian_manager.initialize(guardian);
        };
    }

    #[abi(embed_v0)]
    impl ArgentAccountProfilerImpl of super::IArgentAccountProfiler<ContractState> {
        fn upgrade(ref self: ContractState, new_implementation: ClassHash) {
            replace_class_syscall(new_implementation).unwrap();
        }
    }
}
