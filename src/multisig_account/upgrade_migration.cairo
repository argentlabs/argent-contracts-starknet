#[starknet::interface]
trait IUpgradeMigrationInternal<TContractState> {
    fn migrate_from_before_0_2_0(ref self: TContractState);
    fn migrate_from_0_2_0(ref self: TContractState);
}

#[starknet::component]
mod upgrade_migration_component {
    use argent::multisig_account::signer_manager::interface::IUpgradeMigration;
    use argent::multisig_account::signer_manager::signer_manager::signer_manager_component;
    use super::IUpgradeMigrationInternal;

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
        impl SignerManager: signer_manager_component::HasComponent<TContractState>,
    > of IUpgradeMigrationInternal<ComponentState<TContractState>> {
        fn migrate_from_before_0_2_0(ref self: ComponentState<TContractState>) {
            let mut signer_manager = get_dep_component_mut!(ref self, SignerManager);
            signer_manager.migrate_from_pubkeys_to_guids();
            self.migrate_from_0_2_0();
        }

        fn migrate_from_0_2_0(ref self: ComponentState<TContractState>) {
            let mut signer_manager = get_dep_component_mut!(ref self, SignerManager);
            signer_manager.add_end_marker();
            // Do some health checks?
        }
    }
}
