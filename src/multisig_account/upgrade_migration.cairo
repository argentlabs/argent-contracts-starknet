use argent::account::interface::Version;
use argent::multiowner_account::events::SignerLinked;
use argent::signer::signer_signature::SignerStorageValue;

#[starknet::interface]
trait IUpgradeMigrationInternal<TContractState> {
    fn migrate_from_0_2_0(ref self: TContractState);
}

trait IUpgradeMigrationCallback<TContractState> {
    fn migrate_owners(ref self: TContractState);
    fn emit_signer_linked_event(ref self: TContractState, event: SignerLinked);
}

#[starknet::component]
mod upgrade_migration_component {
    use argent::account::interface::Version;
    use argent::multiowner_account::events::SignerLinked;
    use argent::signer::{signer_signature::{starknet_signer_from_pubkey, SignerTrait}};
    use starknet::storage::Map;
    use super::{IUpgradeMigrationInternal, IUpgradeMigrationCallback};

    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT_LEGACY: usize = 32;

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
        fn migrate_from_0_2_0(ref self: ComponentState<TContractState>) {
            self.migrate_owners();
            // Do some health checks?
        }
    }

    #[generate_trait]
    impl Private<
        TContractState,
        +HasComponent<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
        +Drop<TContractState>,
    > of PrivateTrait<TContractState> {
        fn migrate_owners(ref self: ComponentState<TContractState>) {
            let mut contract = self.get_contract_mut();
            contract.migrate_owners();
        }

        fn emit_signer_linked_event(ref self: ComponentState<TContractState>, event: SignerLinked) {
            let mut contract = self.get_contract_mut();
            contract.emit_signer_linked_event(event);
        }
    }
}
