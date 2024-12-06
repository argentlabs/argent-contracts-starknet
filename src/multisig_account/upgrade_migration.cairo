use argent::signer::signer_signature::SignerStorageValue;

#[starknet::interface]
trait IUpgradeMigrationInternal<TContractState> {
    fn migrate_from_before_0_4_0(ref self: TContractState);
    fn migrate_from_0_4_0(ref self: TContractState);
}

trait IUpgradeMigrationCallback<TContractState> {
    fn finalize_migration(ref self: TContractState);
    fn migrate_owner(ref self: TContractState);
}

#[starknet::component]
mod upgrade_migration_component {
    use super::{IUpgradeMigrationInternal, IUpgradeMigrationCallback};


    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[embeddable_as(UpgradableInternalImpl)]
    impl UpgradableMigrationInternal<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
    > of IUpgradeMigrationInternal<ComponentState<TContractState>> {
        fn migrate_from_before_0_4_0(ref self: ComponentState<TContractState>) {}

        fn migrate_from_0_4_0(ref self: ComponentState<TContractState>) {}
    }

    #[generate_trait]
    impl Private<
        TContractState,
        +HasComponent<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
        +Drop<TContractState>,
    > of PrivateTrait<TContractState> {}
}
