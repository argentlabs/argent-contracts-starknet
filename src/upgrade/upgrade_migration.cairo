use argent::signer::signer_signature::{SignerStorageValue, SignerType};

#[starknet::interface]
trait IUpgradeMigrationInternal<TContractState> {
    fn migrate_from_before_0_4_0(ref self: TContractState);
    fn migrate_from_0_4_0(ref self: TContractState);
}

trait IUpgradeMigrationCallback<TContractState> {
    fn perform_health_check(ref self: TContractState);
    fn initialize_from_upgrade(ref self: TContractState, signer_storage_value: SignerStorageValue);
}

impl U8TryIntoSignerType of TryInto<u8, SignerType> {
    #[inline(always)]
    fn try_into(self: u8) -> Option<SignerType> {
        if self == 0 {
            Option::Some(SignerType::Starknet)
        } else if self == 1 {
            Option::Some(SignerType::Secp256k1)
        } else if self == 2 {
            Option::Some(SignerType::Secp256r1)
        } else if self == 3 {
            Option::Some(SignerType::Eip191)
        } else if self == 4 {
            Option::Some(SignerType::Webauthn)
        } else {
            Option::None
        }
    }
}

#[starknet::component]
mod upgrade_migration_component {
    use argent::account::interface::IEmitArgentAccountEvent;
    use argent::multiowner_account::account_interface::IArgentMultiOwnerAccount;
    use argent::multiowner_account::argent_account::ArgentAccount::Event as ArgentAccountEvent;
    use argent::multiowner_account::events::{EscapeCanceled, SignerLinked};
    use argent::multiowner_account::recovery::Escape;
    use argent::signer::signer_signature::{SignerStorageValue, Signer, starknet_signer_from_pubkey, SignerTrait};
    use argent::upgrade::interface::{IUpgradableCallback, IUpgradeable, IUpgradableCallbackDispatcherTrait};
    use starknet::{
        syscalls::replace_class_syscall, SyscallResultTrait, get_block_timestamp, storage::Map,
        storage_access::{storage_read_syscall, storage_address_from_base_and_offset, storage_base_address_from_felt252,}
    };
    use super::{IUpgradeMigrationInternal, IUpgradeMigrationCallback, U8TryIntoSignerType};

    const LEGACY_ESCAPE_SECURITY_PERIOD: u64 = 7 * 24 * 60 * 60; // 7 days

    #[storage]
    struct Storage {
        // Duplicate keys
        _escape: Escape,
        // Legacy storage
        _signer: felt252,
        _implementation: felt252,
        guardian_escape_attempts: felt252,
        owner_escape_attempts: felt252,
        // 0.4.0
        _signer_non_stark: Map<felt252, felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[embeddable_as(UpgradableInternalImpl)]
    impl UpgradableMigrationInternal<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +IUpgradeMigrationCallback<TContractState>,
        +IArgentMultiOwnerAccount<TContractState>,
        +IEmitArgentAccountEvent<TContractState>,
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
                if get_block_timestamp() < escape_ready_at + LEGACY_ESCAPE_SECURITY_PERIOD {
                    // Not expired. Automatically cancelling the escape when upgrading
                    self.emit_event(ArgentAccountEvent::EscapeCanceled(EscapeCanceled {}));
                }
                // Clear the escape
                self._escape.write(Default::default());
            }

            // Cleaning attempts storage as the escape was cleared
            self.owner_escape_attempts.write(0);
            self.guardian_escape_attempts.write(0);

            // Check basic invariants and emit missing events
            let owner_key = self._signer.read();
            assert(owner_key != 0, 'argent/null-owner');

            let argent_account = self.get_contract();
            let guardian_key = argent_account.get_guardian();
            let guardian_backup_key = argent_account.get_guardian_backup();
            if guardian_key == 0 {
                assert(guardian_backup_key == 0, 'argent/backup-should-be-null');
            } else {
                let guardian = starknet_signer_from_pubkey(guardian_key);
                let guardian_linked = SignerLinked { signer_guid: guardian.into_guid(), signer: guardian };
                self.emit_event(ArgentAccountEvent::SignerLinked(guardian_linked));
                if guardian_backup_key != 0 {
                    let guardian_backup = starknet_signer_from_pubkey(guardian_backup_key);
                    let guardian_backup_linked = SignerLinked {
                        signer_guid: guardian_backup.into_guid(), signer: guardian_backup
                    };
                    self.emit_event(ArgentAccountEvent::SignerLinked(guardian_backup_linked));
                }
            }

            let owner = starknet_signer_from_pubkey(owner_key);
            let owner_linked = SignerLinked { signer_guid: owner.into_guid(), signer: owner };
            self.emit_event(ArgentAccountEvent::SignerLinked(owner_linked));

            let implementation = self._implementation.read();

            if implementation != Zeroable::zero() {
                replace_class_syscall(implementation.try_into().unwrap()).expect('argent/invalid-after-upgrade');
                self._implementation.write(Zeroable::zero());
            }

            self.migrate_from_0_4_0();
        }

        fn migrate_from_0_4_0(ref self: ComponentState<TContractState>) {
            // Reset proxy slot as the replace_class_syscall is done in the upgrade callback
            let implementation = self._implementation.read();

            if implementation != Zeroable::zero() {
                self._implementation.write(Zeroable::zero());
            }

            let starknet_owner_pubkey = self._signer.read();
            if (starknet_owner_pubkey != 0) {
                let stark_signer = starknet_signer_from_pubkey(starknet_owner_pubkey).storage_value();
                self.initialize_from_upgrade(stark_signer);
                self._signer.write(0);
            } else {
                for signer_type_ordinal in 1_u8
                    ..5 {
                        let stored_value = self._signer_non_stark.read(signer_type_ordinal.into());

                        // Can unwrap safely as we are bound by the loop range

                        if (stored_value != 0) {
                            let signer_type = signer_type_ordinal.try_into().unwrap();
                            let signer_storage_value = SignerStorageValue { signer_type, stored_value };
                            self.initialize_from_upgrade(signer_storage_value);
                            self._signer_non_stark.write(signer_type_ordinal.into(), 0);
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
        +IUpgradeMigrationCallback<TContractState>,
        +Drop<TContractState>,
        +IEmitArgentAccountEvent<TContractState>,
    > of PrivateTrait<TContractState> {
        fn emit_event(ref self: ComponentState<TContractState>, event: ArgentAccountEvent) {
            let mut contract = self.get_contract_mut();
            contract.emit_event_callback(event);
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
