use argent::signer::signer_signature::SignerStorageValue;

#[starknet::interface]
trait IUpgradeMigrationInternal<TContractState> {
    fn migrate_from_before_0_4_0(ref self: TContractState);
    fn migrate_from_0_4_0(ref self: TContractState);
}

#[starknet::interface]
trait IUpgradeMigrationCallback<TContractState> {
    fn perform_health_check(ref self: TContractState);
    fn emit_escape_canceled_event(ref self: TContractState);
    fn initialize_from_upgrade(ref self: TContractState, signer_storage_value: SignerStorageValue);
}

#[starknet::component]
mod upgrade_migration_component {
    use argent::multiowner_account::events::SignerLinked;
    use argent::multiowner_account::owner_manager::IOwnerManagerCallback;
    use argent::multiowner_account::recovery::LegacyEscape;
    use argent::signer::signer_signature::{SignerStorageValue, Signer, starknet_signer_from_pubkey, SignerTrait};
    use argent::upgrade::interface::{IUpgradableCallback, IUpgradeable, IUpgradableCallbackDispatcherTrait};
    use starknet::{
        syscalls::replace_class_syscall, SyscallResultTrait, get_block_timestamp,
        storage_access::{
            storage_read_syscall, storage_address_from_base_and_offset, storage_base_address_from_felt252,
            storage_write_syscall
        }
    };
    use super::{IUpgradeMigrationInternal, IUpgradeMigrationCallback};

    const DEFAULT_ESCAPE_SECURITY_PERIOD: u64 = 7 * 24 * 60 * 60; // 7 days

    #[storage]
    struct Storage {
        // Duplicate keys
        _guardian: felt252,
        _guardian_backup: felt252,
        _escape: LegacyEscape,
        // Legacy storage
        _implementation: felt252,
        // 0.4.0
        #[deprecated(feature: "deprecated_legacy_map")]
        _signer_non_stark: LegacyMap<felt252, felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[embeddable_as(UpgradableInternalImpl)]
    impl UpgradableMigrationInternal<
        TContractState,
        +HasComponent<TContractState>,
        +IOwnerManagerCallback<TContractState>,
        +Drop<TContractState>,
        +IUpgradeMigrationCallback<TContractState>
    > of IUpgradeMigrationInternal<ComponentState<TContractState>> {
        fn migrate_from_before_0_4_0(ref self: ComponentState<TContractState>) {
            // As the storage layout for the escape is changing, if there is an ongoing escape it should revert
            // Expired escapes will be cleared
            let escape_base = storage_base_address_from_felt252(selector!("_escape"));
            let escape_ready_at = storage_read_syscall(0, storage_address_from_base_and_offset(escape_base, 0))
                .unwrap_syscall();

            if escape_ready_at == 0 {
                let escape_type = storage_read_syscall(0, storage_address_from_base_and_offset(escape_base, 1))
                    .unwrap_syscall();
                let escape_new_signer = storage_read_syscall(0, storage_address_from_base_and_offset(escape_base, 2))
                    .unwrap_syscall();
                assert(escape_type.is_zero(), 'argent/esc-type-not-null');
                assert(escape_new_signer.is_zero(), 'argent/esc-new-signer-not-null');
            } else {
                let escape_ready_at: u64 = escape_ready_at.try_into().unwrap();
                if get_block_timestamp() < escape_ready_at + DEFAULT_ESCAPE_SECURITY_PERIOD {
                    // Not expired. Automatically cancelling the escape when upgrading
                    self.emit_escape_canceled_event();
                }
                // Clear the escape
                self._escape.write(Default::default());
            }

            // Cleaning attempts storage as the escape was cleared
            let guardian_escape_attempts_storage_address = selector!("guardian_escape_attempts").try_into().unwrap();
            storage_write_syscall(0, guardian_escape_attempts_storage_address, 0).unwrap_syscall();
            let owner_escape_attempts_storage_address = selector!("owner_escape_attempts").try_into().unwrap();
            storage_write_syscall(0, owner_escape_attempts_storage_address, 0).unwrap_syscall();

            // Check basic invariants and emit missing events
            let owner_key_storage_address = selector!("_signer").try_into().unwrap();
            let owner_key = storage_read_syscall(0, owner_key_storage_address).unwrap_syscall();
            let guardian_key = self._guardian.read();
            let guardian_backup_key = self._guardian_backup.read();
            assert(owner_key != 0, 'argent/null-owner');
            if guardian_key == 0 {
                assert(guardian_backup_key == 0, 'argent/backup-should-be-null');
            } else {
                let guardian = starknet_signer_from_pubkey(guardian_key);
                self.emit_signer_linked_event(SignerLinked { signer_guid: guardian.into_guid(), signer: guardian });
                if guardian_backup_key != 0 {
                    let guardian_backup = starknet_signer_from_pubkey(guardian_backup_key);
                    self
                        .emit_signer_linked_event(
                            SignerLinked { signer_guid: guardian_backup.into_guid(), signer: guardian_backup }
                        );
                }
            }

            let owner = starknet_signer_from_pubkey(owner_key);
            self.emit_signer_linked_event(SignerLinked { signer_guid: owner.into_guid(), signer: owner });

            let implementation_storage_address = selector!("_implementation").try_into().unwrap();
            let implementation = storage_read_syscall(0, implementation_storage_address).unwrap_syscall();

            if implementation != Zeroable::zero() {
                replace_class_syscall(implementation.try_into().unwrap()).expect('argent/invalid-after-upgrade');
                storage_write_syscall(0, implementation_storage_address, 0).unwrap_syscall();
            }

            self.migrate_from_0_4_0();
        }

        fn migrate_from_0_4_0(ref self: ComponentState<TContractState>) {
            // Reset proxy slot as the replace_class_syscall is done in the upgrade callback
            let implementation_storage_address = selector!("_implementation").try_into().unwrap();
            let implementation = storage_read_syscall(0, implementation_storage_address).unwrap_syscall();

            if implementation != Zeroable::zero() {
                storage_write_syscall(0, implementation_storage_address, 0).unwrap_syscall();
            }

            let signer_storage_address = selector!("_signer").try_into().unwrap();
            let mut signer_to_migrate = storage_read_syscall(0, signer_storage_address).unwrap_syscall();
            if (signer_to_migrate != 0) {
                let stark_signer = starknet_signer_from_pubkey(signer_to_migrate).storage_value();
                self.initialize_from_upgrade(stark_signer);
                storage_write_syscall(0, signer_storage_address, 0).unwrap_syscall();
            } else {
                for offset in 1_u8
                    ..5 {
                        let stored_value = self._signer_non_stark.read(offset.into());

                        // Can unwrap safely as we are bound by the loop range
                        let signer_type: u256 = offset.into();
                        let signer_type = signer_type.try_into().unwrap();

                        if (stored_value != 0) {
                            let signer_storage_value = SignerStorageValue { signer_type, stored_value };
                            self.initialize_from_upgrade(signer_storage_value);
                            self._signer_non_stark.write(offset.into(), 0);
                            break;
                        }
                    };
            }

            // Health check
            self.perform_health_check();
        }
    }

    #[generate_trait]
    impl Private<
        TContractState,
        +HasComponent<TContractState>,
        +IOwnerManagerCallback<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
        +Drop<TContractState>
    > of PrivateTrait<TContractState> {
        fn emit_signer_linked_event(ref self: ComponentState<TContractState>, event: SignerLinked) {
            let mut contract = self.get_contract_mut();
            contract.emit_signer_linked_event(event);
        }

        fn emit_escape_canceled_event(ref self: ComponentState<TContractState>) {
            let mut contract = self.get_contract_mut();
            contract.emit_escape_canceled_event();
        }

        fn perform_health_check(ref self: ComponentState<TContractState>) {
            let mut contract = self.get_contract_mut();
            contract.perform_health_check();
        }

        fn initialize_from_upgrade(ref self: ComponentState<TContractState>, signer_storage_value: SignerStorageValue) {
            let mut contract = self.get_contract_mut();
            contract.initialize_from_upgrade(signer_storage_value);
        }
    }
}
