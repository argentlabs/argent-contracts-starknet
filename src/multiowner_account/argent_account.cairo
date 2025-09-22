use argent::multiowner_account::argent_account::ArgentAccount::Event;

pub trait IEmitArgentAccountEvent<TContractState> {
    fn emit_event_callback(ref self: TContractState, event: Event);
}
use argent::signer::signer_signature::SignerSignature;

/// @dev Represents a regular signature for the account
/// @dev Escape-related signatures use a single SignerSignature instead. These are signatures for methods that only
/// require one of the two roles to sign the transaction
#[derive(Drop, Copy)]
pub struct AccountSignature {
    pub owner_signature: SignerSignature,
    pub guardian_signature: Option<SignerSignature>,
}

#[starknet::contract(account)]
pub mod ArgentAccount {
    use argent::account::{IAccount, IDeprecatedArgentAccount, Version};
    use argent::introspection::src5_component;
    use argent::multiowner_account::account_interface::{
        IArgentMultiOwnerAccount, IArgentMultiOwnerAccountDispatcher, IArgentMultiOwnerAccountDispatcherTrait,
    };
    use argent::multiowner_account::argent_account::IEmitArgentAccountEvent;
    use argent::multiowner_account::events::{
        AccountCreated, AccountCreatedGuid, EscapeCanceled, EscapeGuardianTriggeredGuid, EscapeOwnerTriggeredGuid,
        EscapeSecurityPeriodChanged, GuardianEscapedGuid, OwnerEscapedGuid, SignerLinked, TransactionExecuted,
    };
    use argent::multiowner_account::guardian_manager::{
        IGuardianManager, guardian_manager_component, guardian_manager_component::IGuardianManagerInternal,
    };
    use argent::multiowner_account::owner_alive::OwnerAlive;
    use argent::multiowner_account::owner_alive::OwnerAliveSignature;
    use argent::multiowner_account::owner_manager::{
        owner_manager_component, owner_manager_component::OwnerManagerInternalImpl,
    };
    use argent::multiowner_account::recovery::{Escape, EscapeType};
    use argent::multiowner_account::upgrade_migration::{
        IUpgradeMigrationCallback, upgrade_migration_component, upgrade_migration_component::IUpgradeMigrationInternal,
    };

    use argent::offchain_message::IOffChainMessageHashRev1;
    use argent::outside_execution::{
        outside_execution::IOutsideExecutionCallback, outside_execution::outside_execution_component,
    };
    use argent::recovery::EscapeStatus;
    use argent::session::session::{ISessionCallback, session_component, session_component::InternalTrait};
    use argent::signer::signer_signature::{
        Signer, SignerSignature, SignerSignatureTrait, SignerStorageTrait, SignerStorageValue, SignerTrait,
        StarknetSignature, StarknetSigner,
    };
    use argent::upgrade::{
        IUpgradableCallback, IUpgradableCallbackOld, upgrade_component, upgrade_component::IUpgradeInternal,
    };
    use argent::utils::array_ext::SpanContains;
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_protocol, assert_only_self},
        calls::{execute_multicall, execute_multicall_with_result}, serialization::{full_deserialize, serialize},
        transaction::tx_v3_max_fee_and_tip,
        transaction_version::{
            DA_MODE_L1, TX_V1, TX_V1_ESTIMATE, TX_V3, TX_V3_ESTIMATE, assert_correct_declare_version,
            assert_correct_deploy_account_version, assert_correct_invoke_version,
        },
    };
    use core::panic_with_felt252;
    use openzeppelin_security::reentrancyguard::{ReentrancyGuardComponent, ReentrancyGuardComponent::InternalImpl};
    use starknet::{
        ClassHash, ContractAddress, VALIDATED, account::Call, get_block_timestamp, get_contract_address,
        get_execution_info, get_tx_info, storage::{StoragePointerReadAccess, StoragePointerWriteAccess},
    };
    use super::AccountSignature;

    const NAME: felt252 = 'ArgentAccount';
    const VERSION: Version = Version { major: 0, minor: 5, patch: 0 };
    const VERSION_COMPAT: felt252 = '0.5.0';

    /// Time it takes for the escape to become ready after being triggered. Also the escape will be
    /// ready and can be completed for this duration
    const DEFAULT_ESCAPE_SECURITY_PERIOD: u64 = 7 * 24 * 60 * 60; // 7 days

    /// Minimum delay between escape attempts (12 hours)
    pub const TIME_BETWEEN_TWO_ESCAPES: u64 = 12 * 60 * 60;

    /// Limits fee in escapes
    const MAX_ESCAPE_MAX_FEE_ETH: u128 = 2000000000000000; // 0.002 ETH
    const MAX_ESCAPE_MAX_FEE_STRK: u128 = 12_000000000000000000; // 12 STRK
    pub const MAX_ESCAPE_TIP_STRK: u128 = 4_000000000000000000; // 4 STRK

    /// Minimum time for the escape security period
    const MIN_ESCAPE_SECURITY_PERIOD: u64 = 60 * 10; // 10 minutes;
    /// Maximum time the change owner message should be valid for
    const ONE_DAY: u64 = 60 * 60 * 24;


    // Owner management
    component!(path: owner_manager_component, storage: owner_manager, event: OwnerManagerEvents);
    #[abi(embed_v0)]
    impl OwnerManager = owner_manager_component::OwnerManagerImpl<ContractState>;
    // Guardian management
    component!(path: guardian_manager_component, storage: guardian_manager, event: GuardianManagerEvents);
    #[abi(embed_v0)]
    impl GuardianManager = guardian_manager_component::GuardianManagerImpl<ContractState>;
    // session
    component!(path: session_component, storage: session, event: SessionableEvents);
    #[abi(embed_v0)]
    impl Sessionable = session_component::SessionImpl<ContractState>;
    // Execute from outside
    component!(path: outside_execution_component, storage: execute_from_outside, event: ExecuteFromOutsideEvents);
    #[abi(embed_v0)]
    impl ExecuteFromOutside = outside_execution_component::OutsideExecutionImpl<ContractState>;
    // Introspection
    component!(path: src5_component, storage: src5, event: SRC5Events);
    #[abi(embed_v0)]
    impl SRC5 = src5_component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Legacy = src5_component::SRC5LegacyImpl<ContractState>;
    // Upgrade
    component!(path: upgrade_component, storage: upgrade, event: UpgradeEvents);
    #[abi(embed_v0)]
    impl Upgradable = upgrade_component::UpgradableImpl<ContractState>;
    // Upgrade migration
    component!(path: upgrade_migration_component, storage: upgrade_migration, event: UpgradeMigrationEvents);
    #[abi(embed_v0)]
    impl FixStorage = upgrade_migration_component::RecoveryFromLegacyUpgradeImpl<ContractState>;
    // Reentrancy guard
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        owner_manager: owner_manager_component::Storage,
        #[substorage(v0)]
        guardian_manager: guardian_manager_component::Storage,
        #[substorage(v0)]
        execute_from_outside: outside_execution_component::Storage,
        #[substorage(v0)]
        src5: src5_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
        #[substorage(v0)]
        upgrade_migration: upgrade_migration_component::Storage,
        #[substorage(v0)]
        session: session_component::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        /// The ongoing escape, if any
        #[allow(starknet::colliding_storage_paths)]
        _escape: Escape,
        /// The following 4 fields are used to limit the number of escapes the account will pay for
        /// Values are Rounded down to the hour:
        /// https://community.starknet.io/t/starknet-v0-13-1-pre-release-notes/113664 Values are
        /// resets when an escape is completed or canceled
        last_guardian_trigger_escape_attempt: u64,
        last_owner_trigger_escape_attempt: u64,
        last_guardian_escape_attempt: u64,
        last_owner_escape_attempt: u64,
        escape_security_period: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnerManagerEvents: owner_manager_component::Event,
        #[flat]
        GuardianManagerEvents: guardian_manager_component::Event,
        #[flat]
        ExecuteFromOutsideEvents: outside_execution_component::Event,
        #[flat]
        SRC5Events: src5_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
        #[flat]
        UpgradeMigrationEvents: upgrade_migration_component::Event,
        #[flat]
        SessionableEvents: session_component::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        TransactionExecuted: TransactionExecuted,
        AccountCreated: AccountCreated,
        AccountCreatedGuid: AccountCreatedGuid,
        EscapeOwnerTriggeredGuid: EscapeOwnerTriggeredGuid,
        EscapeGuardianTriggeredGuid: EscapeGuardianTriggeredGuid,
        OwnerEscapedGuid: OwnerEscapedGuid,
        GuardianEscapedGuid: GuardianEscapedGuid,
        EscapeCanceled: EscapeCanceled,
        SignerLinked: SignerLinked,
        EscapeSecurityPeriodChanged: EscapeSecurityPeriodChanged,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: Signer, guardian: Option<Signer>) {
        let owner_guid = self.owner_manager.initialize(owner);
        let guardian_guid_or_zero = if let Option::Some(guardian) = guardian {
            self.guardian_manager.initialize(guardian)
        } else {
            0
        };

        if let Option::Some(starknet_owner) = owner.starknet_pubkey_or_none() {
            if let Option::Some(guardian) = guardian {
                if let Option::Some(starknet_guardian) = guardian.starknet_pubkey_or_none() {
                    self.emit(AccountCreated { owner: starknet_owner, guardian: starknet_guardian });
                };
            } else {
                self.emit(AccountCreated { owner: starknet_owner, guardian: 0 });
            };
        };
        self.emit(AccountCreatedGuid { owner_guid, guardian_guid: guardian_guid_or_zero });
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let exec_info = get_execution_info();
            let tx_info = exec_info.tx_info;
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            if self.session.is_session(tx_info.signature) {
                self.session.assert_valid_session(calls.span(), tx_info.transaction_hash, tx_info.signature);
            } else {
                self
                    .assert_valid_calls_and_signature(
                        calls: calls.span(),
                        execution_hash: tx_info.transaction_hash,
                        raw_signature: tx_info.signature,
                        is_from_outside: false,
                        account_address: exec_info.contract_address,
                    );
            }
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) {
            self.reentrancy_guard.start();
            let exec_info = get_execution_info();
            let tx_info = exec_info.tx_info;
            assert_only_protocol(exec_info.caller_address);
            assert_correct_invoke_version(tx_info.version);
            let signature = tx_info.signature;
            if self.session.is_session(signature) {
                let session_timestamp = *signature[1];
                // can call unwrap safely as the session has already been deserialized
                let session_timestamp_u64 = session_timestamp.try_into().unwrap();
                assert(session_timestamp_u64 >= exec_info.block_info.block_timestamp, 'session/expired');
            }

            execute_multicall(calls.span());

            self.emit(TransactionExecuted { hash: tx_info.transaction_hash });
            self.reentrancy_guard.end();
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            self.assert_valid_account_signature_raw(hash, signature.span());
            VALIDATED
        }
    }

    // Required Callbacks
    impl EmitArgentAccountEventImpl of IEmitArgentAccountEvent<ContractState> {
        fn emit_event_callback(ref self: ContractState, event: Event) {
            self.emit(event);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        // Called when coming from account v0.2.3 to v0.3.1. Note that accounts v0.2.3.* won't always call this method
        // But v0.3.0+ is guaranteed to call it
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            self.upgrade_migration.migrate_from_before_0_4_0();

            if data.is_empty() {
                return array![];
            }

            let calls: Array<Call> = full_deserialize(data.span()).expect('argent/invalid-calls');
            assert_no_self_call(calls.span(), get_contract_address());

            serialize(@execute_multicall_with_result(calls.span()))
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        // Called when coming from account 0.4.0+
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            assert_only_self();

            // Downgrade check
            let argent_dispatcher = IArgentMultiOwnerAccountDispatcher { contract_address: get_contract_address() };
            assert(argent_dispatcher.get_name() == self.get_name(), 'argent/invalid-name');
            let previous_version = argent_dispatcher.get_version();
            assert(previous_version >= Version { major: 0, minor: 4, patch: 0 }, 'argent/invalid-from-version');
            assert(previous_version < self.get_version(), 'argent/downgrade-not-allowed');

            self.upgrade.complete_upgrade(new_implementation);

            self.upgrade_migration.migrate_from_0_4_0();

            if data.is_empty() {
                return;
            }

            let calls: Array<Call> = full_deserialize(data).expect('argent/invalid-calls');
            assert_no_self_call(calls.span(), get_contract_address());
            execute_multicall(calls.span());
        }
    }

    impl UpgradeMigrationCallbackImpl of IUpgradeMigrationCallback<ContractState> {
        fn finalize_migration(ref self: ContractState) {
            self.owner_manager.assert_valid_storage();
            self.guardian_manager.assert_valid_storage();
            self.clear_escape(escape_canceled: true, reset_timestamps: true);
        }

        fn migrate_owner(ref self: ContractState, signer_storage_value: SignerStorageValue) {
            self.owner_manager.initialize_from_upgrade(signer_storage_value);
        }

        fn migrate_guardians(ref self: ContractState, guardians_storage_value: Array<SignerStorageValue>) {
            self.guardian_manager.migrate_guardians_storage(guardians_storage_value);
        }
    }

    impl OutsideExecutionCallbackImpl of IOutsideExecutionCallback<ContractState> {
        fn execute_from_outside_callback(
            ref self: ContractState, calls: Span<Call>, outside_execution_hash: felt252, raw_signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            if self.session.is_session(raw_signature) {
                self.session.assert_valid_session(calls, outside_execution_hash, raw_signature);
            } else {
                self
                    .assert_valid_calls_and_signature(
                        :calls,
                        execution_hash: outside_execution_hash,
                        :raw_signature,
                        is_from_outside: true,
                        account_address: get_contract_address(),
                    );
            }
            let retdata = execute_multicall_with_result(calls);
            self.emit(TransactionExecuted { hash: outside_execution_hash });
            retdata
        }
    }


    impl SessionCallbackImpl of ISessionCallback<ContractState> {
        fn validate_authorization(
            self: @ContractState, session_hash: felt252, authorization_signature: Span<felt252>,
        ) -> AccountSignature {
            let account_signature = self.parse_account_signature(authorization_signature);
            self.assert_valid_account_signature(session_hash, account_signature);
            account_signature
        }

        fn is_owner_guid(self: @ContractState, owner_guid: felt252) -> bool {
            self.owner_manager.is_owner_guid(owner_guid)
        }

        fn is_guardian_guid(self: @ContractState, guardian_guid: felt252) -> bool {
            self.guardian_manager.is_guardian_guid(guardian_guid)
        }

        fn is_guardian(self: @ContractState, guardian: Signer) -> bool {
            self.guardian_manager.is_guardian(guardian)
        }
    }

    #[abi(embed_v0)]
    impl ArgentMultiOwnerAccountImpl of IArgentMultiOwnerAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let tx_info = get_tx_info();
            assert_correct_declare_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            self.assert_valid_account_signature_raw(tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: Signer,
            guardian: Option<Signer>,
        ) -> felt252 {
            let tx_info = get_tx_info();
            assert_correct_deploy_account_version(tx_info.version);
            assert(tx_info.paymaster_data.is_empty(), 'argent/unsupported-paymaster');
            self.assert_valid_account_signature_raw(tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn set_escape_security_period(ref self: ContractState, new_security_period: u64) {
            assert_only_self();
            assert(new_security_period >= MIN_ESCAPE_SECURITY_PERIOD, 'argent/invalid-security-period');

            let current_escape_status = self.get_escape_status();
            if current_escape_status == EscapeStatus::NotReady || current_escape_status == EscapeStatus::Ready {
                panic_with_felt252('argent/ongoing-escape');
            }
            self.clear_escape(escape_canceled: true, reset_timestamps: true);
            self.escape_security_period.write(new_security_period);
            self.emit(EscapeSecurityPeriodChanged { escape_security_period: new_security_period });
        }

        fn get_escape_security_period(self: @ContractState) -> u64 {
            let storage_value = self.escape_security_period.read();
            if storage_value == 0 {
                DEFAULT_ESCAPE_SECURITY_PERIOD
            } else {
                storage_value
            }
        }

        fn change_owners(
            ref self: ContractState,
            owner_guids_to_remove: Array<felt252>,
            owners_to_add: Array<Signer>,
            owner_alive_signature: Option<OwnerAliveSignature>,
        ) {
            assert_only_self();
            self.owner_manager.change_owners(owner_guids_to_remove, owners_to_add);

            if let Option::Some(owner_alive_signature) = owner_alive_signature {
                self.assert_valid_owner_alive_signature(:owner_alive_signature);
            } // else { validation will ensure it's not needed }
            self.clear_escape(escape_canceled: true, reset_timestamps: true);
        }

        fn change_guardians(
            ref self: ContractState, guardian_guids_to_remove: Array<felt252>, guardians_to_add: Array<Signer>,
        ) {
            assert_only_self();
            self.guardian_manager.change_guardians(:guardian_guids_to_remove, :guardians_to_add);
            self.clear_escape(escape_canceled: true, reset_timestamps: true);
        }

        fn trigger_escape_owner(ref self: ContractState, new_owner: Signer) {
            assert_only_self();

            // no escape if there is a guardian escape triggered by the owner in progress
            let (current_escape, current_escape_status) = self.get_escape_and_status();
            if current_escape.escape_type == EscapeType::Guardian {
                assert(current_escape_status == EscapeStatus::Expired, 'argent/cannot-override-escape');
            }

            self.clear_escape(escape_canceled: true, reset_timestamps: false);

            let ready_at = get_block_timestamp() + self.get_escape_security_period();
            let escape = Escape {
                ready_at, escape_type: EscapeType::Owner, new_signer: Option::Some(new_owner.storage_value()),
            };
            self._escape.write(escape);

            let new_owner_guid = new_owner.into_guid();

            self.emit(EscapeOwnerTriggeredGuid { ready_at, new_owner_guid: new_owner_guid });
            self.emit(SignerLinked { signer_guid: new_owner_guid, signer: new_owner });
        }

        fn trigger_escape_guardian(ref self: ContractState, new_guardian: Option<Signer>) {
            assert_only_self();
            self.clear_escape(escape_canceled: true, reset_timestamps: false);

            let (new_guardian_guid, new_guardian_storage_value) = if let Option::Some(guardian) = new_guardian {
                let guardian_guid = guardian.into_guid();
                self.emit(SignerLinked { signer_guid: guardian_guid, signer: guardian });
                (guardian_guid, Option::Some(guardian.storage_value()))
            } else {
                (0, Option::None)
            };

            let ready_at = get_block_timestamp() + self.get_escape_security_period();
            let escape = Escape { ready_at, escape_type: EscapeType::Guardian, new_signer: new_guardian_storage_value };
            self._escape.write(escape);
            self.emit(EscapeGuardianTriggeredGuid { ready_at, new_guardian_guid });
        }

        fn escape_owner(ref self: ContractState) {
            assert_only_self();

            // assert_valid_calls_and_signature(...) guarantees that the escape is of the correct type
            let (current_escape, current_escape_status) = self.get_escape_and_status();
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            // update owner
            let new_owner = current_escape.new_signer.unwrap();
            self.owner_manager.complete_owner_escape(:new_owner);
            self.emit(OwnerEscapedGuid { new_owner_guid: new_owner.into_guid() });

            self.clear_escape(escape_canceled: false, reset_timestamps: true);
        }

        fn escape_guardian(ref self: ContractState) {
            assert_only_self();

            // assert_valid_calls_and_signature(...) guarantees that the escape is of the correct type

            let (current_escape, current_escape_status) = self.get_escape_and_status();
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            let new_guardian = current_escape.new_signer;
            self.guardian_manager.complete_guardian_escape(:new_guardian);
            if let Option::Some(new_guardian) = new_guardian {
                self.emit(GuardianEscapedGuid { new_guardian_guid: new_guardian.into_guid() });
            } else {
                self.emit(GuardianEscapedGuid { new_guardian_guid: 0 });
            }

            self.clear_escape(escape_canceled: false, reset_timestamps: true);
        }

        fn cancel_escape(ref self: ContractState) {
            assert_only_self();
            assert(self.get_escape_status() != EscapeStatus::None, 'argent/invalid-escape');
            self.clear_escape(escape_canceled: true, reset_timestamps: true);
        }

        fn get_escape(self: @ContractState) -> Escape {
            self._escape.read()
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            VERSION
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        fn get_last_owner_trigger_escape_attempt(self: @ContractState) -> u64 {
            self.last_owner_trigger_escape_attempt.read()
        }

        fn get_last_guardian_trigger_escape_attempt(self: @ContractState) -> u64 {
            self.last_guardian_trigger_escape_attempt.read()
        }

        fn get_last_guardian_escape_attempt(self: @ContractState) -> u64 {
            self.last_guardian_escape_attempt.read()
        }

        fn get_last_owner_escape_attempt(self: @ContractState) -> u64 {
            self.last_owner_escape_attempt.read()
        }

        /// Current escape if any, and its status
        fn get_escape_and_status(self: @ContractState) -> (Escape, EscapeStatus) {
            let current_escape = self._escape.read();
            let escape_ready_at = current_escape.ready_at;
            if escape_ready_at == 0 {
                return (current_escape, EscapeStatus::None);
            }

            let block_timestamp = get_block_timestamp();
            if block_timestamp < escape_ready_at {
                return (current_escape, EscapeStatus::NotReady);
            }
            if escape_ready_at + self.get_escape_security_period() <= block_timestamp {
                return (current_escape, EscapeStatus::Expired);
            }
            (current_escape, EscapeStatus::Ready)
        }
    }

    #[abi(embed_v0)]
    impl DeprecatedArgentAccountImpl of IDeprecatedArgentAccount<ContractState> {
        fn getVersion(self: @ContractState) -> felt252 {
            VERSION_COMPAT
        }

        fn getName(self: @ContractState) -> felt252 {
            self.get_name()
        }

        fn isValidSignature(self: @ContractState, hash: felt252, signatures: Array<felt252>) -> felt252 {
            assert(self.is_valid_signature(hash, signatures) == VALIDATED, 'argent/invalid-signature');
            1
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls_and_signature(
            ref self: ContractState,
            calls: Span<Call>,
            execution_hash: felt252,
            raw_signature: Span<felt252>,
            is_from_outside: bool,
            account_address: ContractAddress,
        ) {
            if calls.len() == 1 {
                let call = calls.at(0);
                if *call.to == account_address {
                    let selector = *call.selector;

                    if selector == selector!("trigger_escape_owner") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_guardian_trigger_escape_attempt.read());
                            self.last_guardian_trigger_escape_attempt.write(get_block_timestamp());
                        }
                        let new_owner = full_deserialize::<Signer>(*call.calldata).expect('argent/invalid-calldata');
                        assert(!self.owner_manager.is_owner(new_owner), 'argent/new-owner-is-owner');
                        // valid guardian signature also asserts that a guardian is set
                        self.guardian_manager.assert_single_guardian_signature(execution_hash, raw_signature);
                        return; // valid
                    }
                    if selector == selector!("escape_owner") {
                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_guardian_escape_attempt.read());
                            self.last_guardian_escape_attempt.write(get_block_timestamp());
                        }

                        assert((*call.calldata).is_empty(), 'argent/invalid-calldata');
                        let current_escape = self._escape.read();
                        assert(current_escape.escape_type == EscapeType::Owner, 'argent/invalid-escape');
                        // valid guardian signature also asserts that a guardian is set
                        self.guardian_manager.assert_single_guardian_signature(execution_hash, raw_signature);
                        return; // valid
                    }
                    if selector == selector!("trigger_escape_guardian") {
                        self.guardian_manager.assert_guardian_set();

                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_owner_trigger_escape_attempt.read());
                            self.last_owner_trigger_escape_attempt.write(get_block_timestamp());
                        }

                        let new_guardian_opt = full_deserialize::<Option<Signer>>(*call.calldata)
                            .expect('argent/invalid-calldata');
                        if let Option::Some(new_guardian) = new_guardian_opt {
                            assert(!self.guardian_manager.is_guardian(new_guardian), 'argent/new-guardian-is-guardian');
                        }
                        self.owner_manager.assert_single_owner_signature(execution_hash, raw_signature);
                        return; // valid
                    }
                    if selector == selector!("escape_guardian") {
                        self.guardian_manager.assert_guardian_set();

                        if !is_from_outside {
                            assert_valid_escape_parameters(self.last_owner_escape_attempt.read());
                            self.last_owner_escape_attempt.write(get_block_timestamp());
                        }
                        assert((*call.calldata).is_empty(), 'argent/invalid-calldata');
                        let current_escape = self._escape.read();

                        assert(current_escape.escape_type == EscapeType::Guardian, 'argent/invalid-escape');
                        self.owner_manager.assert_single_owner_signature(execution_hash, raw_signature);
                        return; // valid
                    }
                    if selector == selector!("change_owners") {
                        let account_signature = self.parse_account_signature(raw_signature);
                        if !self.guardian_manager.has_guardian() {
                            let (owner_guids_to_remove, _, owner_alive_signature) = full_deserialize::<
                                (Array<felt252>, Array<Signer>, Option<OwnerAliveSignature>),
                            >(*call.calldata)
                                .expect('argent/invalid-calldata');

                            let signer_still_valid = !owner_guids_to_remove
                                .span()
                                .contains(account_signature.owner_signature.signer().into_guid());

                            assert(signer_still_valid || owner_alive_signature.is_some(), 'argent/missing-owner-alive');
                        }
                        self.assert_valid_account_signature(execution_hash, account_signature);
                        return; // valid
                    }
                    assert(selector != selector!("execute_after_upgrade"), 'argent/forbidden-call');
                    assert(selector != selector!("perform_upgrade"), 'argent/forbidden-call');
                }
            } else {
                // make sure no call is to the account
                assert_no_self_call(calls, account_address);
            }
            self.assert_valid_account_signature_raw(execution_hash, raw_signature);
        }

        fn parse_account_signature(self: @ContractState, mut raw_signature: Span<felt252>) -> AccountSignature {
            // Check if it's a concise signature.
            // The account only support concise signatures if: There is only one owner and it's a StarknetSigner and
            // there is no guardian or there's only one guardian and it's a StarknetSigner
            // Concise signatures are always 2 or 4 items long but shortest signature in the regular
            // format is at least 5 items: [array_len, signature_type, signer_pubkey, r, s]
            if raw_signature.len() != 2 && raw_signature.len() != 4 {
                // Parse regular signature. Manual inlining instead of calling full_deserialize for performance
                let signature_count = *raw_signature.pop_front().expect('argent/invalid-signature-format');
                if signature_count == 1 {
                    let owner_signature: SignerSignature = Serde::deserialize(ref raw_signature)
                        .expect('argent/invalid-signature-format');
                    assert(raw_signature.is_empty(), 'argent/invalid-signature-length');
                    return AccountSignature { owner_signature, guardian_signature: Option::None };
                } else if signature_count == 2 {
                    let owner_signature: SignerSignature = Serde::deserialize(ref raw_signature)
                        .expect('argent/invalid-signature-format');
                    let guardian_signature: SignerSignature = Serde::deserialize(ref raw_signature)
                        .expect('argent/invalid-signature-format');
                    assert(raw_signature.is_empty(), 'argent/invalid-signature-length');
                    return AccountSignature { owner_signature, guardian_signature: Option::Some(guardian_signature) };
                } else {
                    core::panic_with_felt252('argent/invalid-signature-length');
                };
            };

            let single_stark_owner = self
                .owner_manager
                .get_single_stark_owner_pubkey()
                .expect('argent/no-single-stark-owner');
            let owner_signature = SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: single_stark_owner.try_into().expect('argent/zero-pubkey') },
                    StarknetSignature {
                        r: *raw_signature.pop_front().unwrap(), s: *raw_signature.pop_front().unwrap(),
                    },
                ),
            );
            if raw_signature.is_empty() {
                return AccountSignature { owner_signature, guardian_signature: Option::None };
            }

            let single_stark_guardian = self.guardian_manager.get_single_stark_guardian_pubkey();

            let guardian_signature = SignerSignature::Starknet(
                (
                    StarknetSigner { pubkey: single_stark_guardian.try_into().expect('argent/zero-pubkey') },
                    StarknetSignature {
                        r: *raw_signature.pop_front().unwrap(), s: *raw_signature.pop_front().unwrap(),
                    },
                ),
            );
            return AccountSignature { owner_signature, guardian_signature: Option::Some(guardian_signature) };
        }
        #[inline(always)]
        fn assert_valid_account_signature_raw(self: @ContractState, hash: felt252, raw_signature: Span<felt252>) {
            self.assert_valid_account_signature(hash, self.parse_account_signature(raw_signature));
        }

        #[inline(always)]
        fn assert_valid_account_signature(self: @ContractState, hash: felt252, account_signature: AccountSignature) {
            assert(self.is_valid_owner_signature(hash, account_signature.owner_signature), 'argent/invalid-owner-sig');
            if let Option::Some(guardian_signature) = account_signature.guardian_signature {
                assert(self.is_valid_guardian_signature(hash, guardian_signature), 'argent/invalid-guardian-sig');
            } else {
                assert(!self.guardian_manager.has_guardian(), 'argent/missing-guardian-sig');
            };
        }

        /// The message hash is the result of hashing the SNIP-12 compliant object OwnerAlive
        fn assert_valid_owner_alive_signature(self: @ContractState, owner_alive_signature: OwnerAliveSignature) {
            let signature_expiration = owner_alive_signature.signature_expiration;
            let owner_signature = owner_alive_signature.owner_signature;
            assert(signature_expiration >= get_block_timestamp(), 'argent/expired-signature');
            assert(signature_expiration - get_block_timestamp() <= ONE_DAY, 'argent/timestamp-too-far-future');
            let new_owner_guid = owner_signature.signer().into_guid();
            assert(self.owner_manager.is_owner_guid(new_owner_guid), 'argent/invalid-sig-not-owner');
            let message_hash = OwnerAlive { new_owner_guid, signature_expiration }.get_message_hash_rev_1();
            let is_valid = owner_signature.is_valid_signature(message_hash);
            assert(is_valid, 'argent/invalid-alive-sig');
        }

        fn get_escape_status(self: @ContractState) -> EscapeStatus {
            let (_, current_escape_status) = self.get_escape_and_status();
            current_escape_status
        }

        /// Clear the escape from storage
        /// @param escape_completed Whether the escape was completed successfully, in case it wasn't, EscapeCanceled
        /// could be emitted @param reset_timestamps Whether to reset the timestamps for gas griefing protection
        fn clear_escape(ref self: ContractState, escape_canceled: bool, reset_timestamps: bool) {
            if escape_canceled {
                // Emit Canceled event if needed
                let current_escape_status = self.get_escape_status();
                if current_escape_status == EscapeStatus::NotReady || current_escape_status == EscapeStatus::Ready {
                    self.emit(EscapeCanceled {});
                }
            }
            self._escape.write(Default::default());
            if reset_timestamps {
                self.last_owner_trigger_escape_attempt.write(0);
                self.last_guardian_trigger_escape_attempt.write(0);
                self.last_owner_escape_attempt.write(0);
                self.last_guardian_escape_attempt.write(0);
            }
        }
    }

    fn assert_valid_escape_parameters(last_timestamp: u64) {
        let tx_info = get_tx_info().unbox();
        if tx_info.version == TX_V3 || tx_info.version == TX_V3_ESTIMATE {
            // No need for modes other than L1 while escaping
            assert(
                tx_info.nonce_data_availability_mode == DA_MODE_L1 && tx_info.fee_data_availability_mode == DA_MODE_L1,
                'argent/invalid-da-mode',
            );

            // No need to allow self deployment and escaping in one transaction
            assert(tx_info.account_deployment_data.is_empty(), 'argent/invalid-deployment-data');

            let (max_fee, max_tip) = tx_v3_max_fee_and_tip(tx_info);
            // Limit the maximum tip and maximum total fee while escaping
            assert(max_tip <= MAX_ESCAPE_TIP_STRK, 'argent/tip-too-high');
            assert(max_fee <= MAX_ESCAPE_MAX_FEE_STRK, 'argent/max-fee-too-high');
        } else if tx_info.version == TX_V1 || tx_info.version == TX_V1_ESTIMATE {
            // other fields not available on V1
            assert(tx_info.max_fee <= MAX_ESCAPE_MAX_FEE_ETH, 'argent/max-fee-too-high');
        } else {
            panic_with_felt252('argent/invalid-tx-version');
        }

        assert(get_block_timestamp() > last_timestamp + TIME_BETWEEN_TWO_ESCAPES, 'argent/last-escape-too-recent');
    }
}
