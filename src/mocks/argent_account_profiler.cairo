/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes. Please refrain from relying on the
/// functionality of this contract for any production. 🚨

use argent::account::Version;
use argent::signer::signer_signature::Signer;

// Those functions are called when upgrading
#[starknet::interface]
trait IArgentAccountProfiler<TContractState> {
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: Signer,
        guardian: Option<Signer>,
    ) -> felt252;
    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
}


#[starknet::contract(account)]
mod ArgentAccountProfile {
    use argent::account::{IAccount, Version};
    use argent::multiowner_account::argent_account::ArgentAccount::Event as ArgentAccountEvent;
    use argent::multiowner_account::argent_account::IEmitArgentAccountEvent;
    use argent::multiowner_account::guardian_manager::{
        guardian_manager_component, guardian_manager_component::GuardianManagerInternal,
    };
    use argent::multiowner_account::owner_manager::{
        owner_manager_component, owner_manager_component::OwnerManagerInternalImpl,
    };
    use argent::signer::signer_signature::Signer;
    use argent::upgrade::{
        IUpgradableCallback, IUpgradableCallbackOld, upgrade_component, upgrade_component::UpgradableInternalImpl,
    };
    use argent::utils::calls::execute_multicall;
    use starknet::{ClassHash, VALIDATED, account::Call};

    const NAME: felt252 = 'ArgentAccount';
    const VERSION: Version = Version { major: 0, minor: 4, patch: 0 };

    // Do We use that or do I go even further?
    // Owner management
    component!(path: owner_manager_component, storage: owner_manager, event: OwnerManagerEvents);
    #[abi(embed_v0)]
    impl OwnerManager = owner_manager_component::OwnerManagerImpl<ContractState>;
    // Do We use that or do I go even further?
    // Guardian management
    component!(path: guardian_manager_component, storage: guardian_manager, event: GuardianManagerEvents);
    #[abi(embed_v0)]
    impl GuardianManager = guardian_manager_component::GuardianManagerImpl<ContractState>;
    // Upgrade
    component!(path: upgrade_component, storage: upgrade, event: UpgradeEvents);
    #[abi(embed_v0)]
    impl Upgradable = upgrade_component::UpgradableImpl<ContractState>;

    #[abi(embed_v0)]
    #[storage]
    struct Storage {
        #[substorage(v0)]
        owner_manager: owner_manager_component::Storage,
        #[substorage(v0)]
        guardian_manager: guardian_manager_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnerManagerEvents: owner_manager_component::Event,
        #[flat]
        GuardianManagerEvents: guardian_manager_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: Signer, guardian: Option<Signer>) {
        self.owner_manager.initialize(owner);
        if let Option::Some(guardian) = guardian {
            self.guardian_manager.initialize(guardian);
        };
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) {
            execute_multicall(calls.span());
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            VALIDATED
        }
    }

    // Required Callbacks
    impl EmitArgentAccountEventImpl of IEmitArgentAccountEvent<ContractState> {
        fn emit_event_callback(ref self: ContractState, event: ArgentAccountEvent) {}
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        // Called when coming from account v0.2.3 to v0.3.1. Note that accounts v0.2.3.* won't always call this method
        // But v0.3.0+ is guaranteed to call it
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            array![]
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        // As we have the correct layout already, no need to do anything
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {}
    }

    #[abi(embed_v0)]
    impl ArgentAccountProfilerImpl of super::IArgentAccountProfiler<ContractState> {
        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: Signer,
            guardian: Option<Signer>,
        ) -> felt252 {
            VALIDATED
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }
        fn get_version(self: @ContractState) -> Version {
            VERSION
        }

        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            true
        }
    }
}
