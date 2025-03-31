use argent::signer::signer_signature::SignerStorageValue;

pub trait IUpgradeMigrationCallback<TContractState> {
    fn finalize_migration(ref self: TContractState);
    fn migrate_owner(ref self: TContractState, signer_storage_value: SignerStorageValue);
    fn migrate_guardians(ref self: TContractState, guardians_storage_value: Array<SignerStorageValue>);
}

/// Trait for recovering upon an upgrade that wasn't done correctly.
///
/// This can happen if the contract was upgraded from 0.2.3.* with an empty calldata array.
/// This function should make all the checks and changes necessary to ensure the contract is in a valid state.
#[starknet::interface]
trait IRecoveryFromLegacyUpgrade<TContractState> {
    fn recovery_from_legacy_upgrade(ref self: TContractState);
}

/// @notice Legacy escape data structure for <0.4.0 versions
/// @dev Used to read escape data during upgrades
#[derive(Drop, Copy, Serde, Default, starknet::Store)]
struct LegacyEscape {
    // Timestamp when escape becomes active (0 if no escape)
    ready_at: u64,
    // Type of escape: None (0x0), Guardian (0x1), Owner (0x2)
    escape_type: felt252,
    // starknet pub key of the new owner/guardian
    new_signer: felt252,
}

#[starknet::component]
pub mod upgrade_migration_component {
    use argent::multiowner_account::account_interface::IArgentMultiOwnerAccount;
    use argent::multiowner_account::argent_account::ArgentAccount::Event as ArgentAccountEvent;
    use argent::multiowner_account::argent_account::IEmitArgentAccountEvent;
    use argent::multiowner_account::events::{EscapeCanceled, SignerLinked};
    use argent::multiowner_account::owner_manager::{IOwnerManager, owner_manager_component};
    use argent::signer::signer_signature::{
        Signer, SignerStorageValue, SignerTrait, SignerType, starknet_signer_from_pubkey,
    };
    use core::num::traits::Zero;
    use starknet::storage::{
        StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{get_block_timestamp, storage::Map, syscalls::replace_class_syscall};
    use super::{IRecoveryFromLegacyUpgrade, IUpgradeMigrationCallback, LegacyEscape};

    const LEGACY_ESCAPE_SECURITY_PERIOD: u64 = 7 * 24 * 60 * 60; // 7 days

    #[storage]
    pub struct Storage {
        // Implementation address for proxy used before 0.3.0
        _implementation: felt252,
        // Single owner's Starknet public key before 0.5.0
        _signer: felt252,
        // Non-Starknet type owner data (added in 0.4.0, removed in 0.5.0)
        _signer_non_stark: Map<felt252, felt252>,
        // Main guardian's Starknet public key before 0.5.0
        _guardian: felt252,
        // Backup guardian's Starknet public key before 0.5.0
        _guardian_backup: felt252,
        // Non-Starknet type backup guardian data (added in 0.4.0, removed in 0.5.0)
        _guardian_backup_non_stark: Map<felt252, felt252>,
        // Legacy escape data before 0.4.0 (different storage layout)
        _escape: LegacyEscape,
        // Legacy escape attempt counters
        guardian_escape_attempts: felt252,
        owner_escape_attempts: felt252,
        // Current nonce used up to 0.2.3.1
        _current_nonce: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}


    #[embeddable_as(RecoveryFromLegacyUpgradeImpl)]
    impl RecoveryFromLegacyUpgrade<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
        +IArgentMultiOwnerAccount<TContractState>,
        +IEmitArgentAccountEvent<TContractState>,
        impl OwnerManager: owner_manager_component::HasComponent<TContractState>,
    > of IRecoveryFromLegacyUpgrade<ComponentState<TContractState>> {
        fn recovery_from_legacy_upgrade(ref self: ComponentState<TContractState>) {
            // Ensuring there is a signer to recover
            assert(self._signer.read() != 0, 'argent/no-signer-to-recover');
            assert(self._implementation.read() != 0, 'argent/wrong-implementation');
            let owner_manager = get_dep_component!(@self, OwnerManager);
            assert(owner_manager.get_owners_guids().len() == 0, 'argent/owner-not-empty');

            self.migrate_from_before_0_4_0();

            // Ensuring the recovery was successful
            assert(self._signer.read() == 0, 'argent/signer-not-removed');
            assert(self._implementation.read() == 0, 'argent/impl-not-removed');
            assert(owner_manager.get_owners_guids().len() == 1, 'argent/owner-not-migrated');
        }
    }

    #[generate_trait]
    pub impl UpgradeMigrationInternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
        +IArgentMultiOwnerAccount<TContractState>,
        +IEmitArgentAccountEvent<TContractState>,
    > of IUpgradeMigrationInternal<TContractState> {
        fn migrate_from_before_0_4_0(ref self: ComponentState<TContractState>) {
            let legacy_escape = self._escape.read();
            if legacy_escape.ready_at != 0 && get_block_timestamp() < legacy_escape.ready_at
                + LEGACY_ESCAPE_SECURITY_PERIOD {
                // Active escape. Automatically cancelling the escape with the upgrade
                self.emit_event(ArgentAccountEvent::EscapeCanceled(EscapeCanceled {}));
            }
            // Clear the escape
            self._escape.write(Default::default());

            // Cleaning attempts storage as the escape was cleared
            self.owner_escape_attempts.write(0);
            self.guardian_escape_attempts.write(0);

            // Check basic invariants and emit missing events
            let owner_key = self._signer.read();
            assert(owner_key != 0, 'argent/null-owner');

            let owner = starknet_signer_from_pubkey(owner_key);
            self.emit_signer_linked(owner.into_guid(), owner);

            let guardian_key = self._guardian.read();
            let guardian_backup_key = self._guardian_backup.read();
            assert(!(guardian_key == 0 && guardian_backup_key != 0), 'argent/backup-should-be-null');

            if guardian_key != 0 {
                let guardian = starknet_signer_from_pubkey(guardian_key);
                self.emit_signer_linked(guardian.into_guid(), guardian);
                if guardian_backup_key != 0 {
                    let guardian_backup = starknet_signer_from_pubkey(guardian_backup_key);
                    self.emit_signer_linked(guardian_backup.into_guid(), guardian_backup);
                };
            }

            let implementation = self._implementation.read();

            if implementation != Zero::zero() {
                replace_class_syscall(implementation.try_into().unwrap()).expect('argent/invalid-after-upgrade');
                self._implementation.write(Zero::zero());
            }

            self.migrate_from_0_4_0();
        }

        fn migrate_from_0_4_0(ref self: ComponentState<TContractState>) {
            // Reset proxy slot, changing the ClassHash is done in the upgrade callback
            self._implementation.write(0);
            // During an upgrade we changed the layout from being 3 fields to 3 fields packed onto 2 fields.
            // We need to restore that third field that could have been left behind.
            self._escape.new_signer.write(0);
            // Reset the nonce to 0 to clean up the storage
            self._current_nonce.write(0);

            let mut contract = self.get_contract_mut();

            let starknet_owner_pubkey = self._signer.read();
            if (starknet_owner_pubkey != 0) {
                contract.migrate_owner(starknet_signer_from_pubkey(starknet_owner_pubkey).storage_value());
                self._signer.write(0);
            } else {
                for signer_type in array![
                    SignerType::Webauthn, SignerType::Secp256k1, SignerType::Secp256r1, SignerType::Eip191,
                ] {
                    let stored_value = self._signer_non_stark.read(signer_type.into());
                    if (stored_value != 0) {
                        let signer_storage_value = SignerStorageValue { signer_type, stored_value };
                        contract.migrate_owner(signer_storage_value);
                        self._signer_non_stark.write(signer_type.into(), 0);
                        break;
                    }
                };
            }
            let mut guardians_to_migrate = array![];
            let guardian_starknet_pubkey = self._guardian.read();
            if guardian_starknet_pubkey != 0 {
                guardians_to_migrate.append(starknet_signer_from_pubkey(guardian_starknet_pubkey).storage_value());
                self._guardian.write(0);
            };

            let guardian_backup_starknet_pubkey = self._guardian_backup.read();
            if guardian_backup_starknet_pubkey != 0 {
                guardians_to_migrate
                    .append(starknet_signer_from_pubkey(guardian_backup_starknet_pubkey).storage_value());
                self._guardian_backup.write(0);
            } else {
                for signer_type in array![
                    SignerType::Webauthn, SignerType::Secp256k1, SignerType::Secp256r1, SignerType::Eip191,
                ] {
                    let stored_value = self._guardian_backup_non_stark.read(signer_type.into());
                    if (stored_value != 0) {
                        guardians_to_migrate.append(SignerStorageValue { signer_type, stored_value });
                        self._guardian_backup_non_stark.write(signer_type.into(), 0);
                        break;
                    }
                };
            };
            if guardians_to_migrate.len() > 0 {
                contract.migrate_guardians(guardians_to_migrate);
            }

            // Health check
            self.finalize_migration();
        }
    }

    #[generate_trait]
    impl Private<
        TContractState,
        +HasComponent<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
        +Drop<TContractState>,
        +IEmitArgentAccountEvent<TContractState>,
    > of PrivateTrait<TContractState> {
        fn emit_event(ref self: ComponentState<TContractState>, event: ArgentAccountEvent) {
            let mut contract = self.get_contract_mut();
            contract.emit_event_callback(event);
        }

        fn emit_signer_linked(ref self: ComponentState<TContractState>, signer_guid: felt252, signer: Signer) {
            let signer_linked = SignerLinked { signer_guid, signer };
            self.emit_event(ArgentAccountEvent::SignerLinked(signer_linked));
        }

        fn finalize_migration(ref self: ComponentState<TContractState>) {
            let mut contract = self.get_contract_mut();
            contract.finalize_migration();
        }

        fn migrate_owner(ref self: ComponentState<TContractState>, signer_storage_value: SignerStorageValue) {
            let mut contract = self.get_contract_mut();
            contract.migrate_owner(signer_storage_value);
        }
    }
}
