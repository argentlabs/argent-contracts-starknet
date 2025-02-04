#[starknet::interface]
trait IUpgradeMigrationInternal<TContractState> {
    fn migrate_from_before_0_2_0(ref self: TContractState);
    fn migrate_from_0_2_0(ref self: TContractState);
}
/// @notice This implementation relies on the `SignerManager` component to perform the migration.
/// If that component's logic is changed, this could break the migration.
#[starknet::component]
pub mod upgrade_migration_component {
    use argent::multisig_account::signer_manager::{IUpgradeMigration, signer_manager_component};
    use super::IUpgradeMigrationInternal;

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(UpgradableMigrationInternalImpl)]
    impl UpgradableMigrationInternal<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl SignerManager: signer_manager_component::HasComponent<TContractState>,
    > of IUpgradeMigrationInternal<ComponentState<TContractState>> {
        fn migrate_from_before_0_2_0(ref self: ComponentState<TContractState>) {
            let mut signer_manager = get_dep_component_mut!(ref self, SignerManager);
            signer_manager.add_end_marker();
            signer_manager.migrate_from_pubkeys_to_guids();
            self.migrate_from_0_2_0();
        }

        fn migrate_from_0_2_0(ref self: ComponentState<TContractState>) {
            let mut signer_manager = get_dep_component_mut!(ref self, SignerManager);
            signer_manager.add_end_marker();
        }
    }
}
