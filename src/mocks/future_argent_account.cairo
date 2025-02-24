/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes. Please refrain from relying on the
/// functionality of this contract for any production. 🚨
use argent::account::Version;
use argent::signer::signer_signature::Signer;

#[starknet::interface]
trait IFutureArgentUserAccount<TContractState> {
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: Signer,
        guardian: Option<Signer>,
    ) -> felt252;
    fn get_owner(self: @TContractState) -> felt252;
    fn get_guardian(self: @TContractState) -> felt252;

    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
}

#[starknet::contract(account)]
mod MockFutureArgentAccount {
    use argent::account::{IAccount, Version};
    use argent::introspection::src5_component;
    use argent::multiowner_account::argent_account::AccountSignature;
    use argent::signer::signer_signature::{Signer, SignerSignature, SignerSignatureTrait, SignerTrait, SignerType};
    use argent::upgrade::{
        IUpgradableCallback, IUpgradableCallbackOld, upgrade_component, upgrade_component::UpgradableInternalImpl,
    };

    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_self}, calls::execute_multicall, serialization::full_deserialize,
    };
    use starknet::{
        ClassHash, VALIDATED, account::Call, get_contract_address, get_tx_info,
        storage::{StoragePointerReadAccess, StoragePointerWriteAccess},
    };
    use super::{IFutureArgentUserAccountDispatcher, IFutureArgentUserAccountDispatcherTrait};

    const NAME: felt252 = 'ArgentAccount';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 6;
    const VERSION_PATCH: u8 = 0;
    const VERSION_COMPAT: felt252 = '0.6.0';

    // Introspection
    component!(path: src5_component, storage: src5, event: SRC5Events);
    #[abi(embed_v0)]
    impl SRC5 = src5_component::SRC5Impl<ContractState>;
    // Upgrade
    component!(path: upgrade_component, storage: upgrade, event: UpgradeEvents);
    #[abi(embed_v0)]
    impl Upgradable = upgrade_component::UpgradableImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: src5_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
        _signer: felt252,
        _guardian: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Events: src5_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: Signer, guardian: Option<Signer>) {
        assert(owner.signer_type() == SignerType::Starknet, 'argent/owner-must-be-starknet');
        self._signer.write(owner.storage_value().stored_value);
        if let Option::Some(guardian) = guardian {
            assert(guardian.signer_type() == SignerType::Starknet, 'argent/guardian-must-be-stark');
            self._guardian.write(guardian.storage_value().stored_value);
        };
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let tx_info = get_tx_info();
            self.assert_valid_calls_and_signature(calls.span(), tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) {
            execute_multicall(calls.span())
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            self.assert_valid_account_signature(hash, self.parse_account_signature(signature.span()));
            VALIDATED
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        // Called when coming from account < 0.4.0
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            core::panic_with_felt252('argent/no-direct-upgrade');
            array![]
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        // Called when coming from account 0.4.0+
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            assert_only_self();
            let previous_version = IFutureArgentUserAccountDispatcher { contract_address: get_contract_address() }
                .get_version();
            assert(previous_version >= Version { major: 0, minor: 4, patch: 0 }, 'argent/invalid-from-version');
            assert(previous_version < self.get_version(), 'argent/downgrade-not-allowed');
            self.upgrade.complete_upgrade(new_implementation);
            if data.is_empty() {
                return;
            }
            let calls: Array<Call> = full_deserialize(data).expect('argent/invalid-calls');
            assert_no_self_call(calls.span(), get_contract_address());
            execute_multicall(calls.span());
        }
    }

    #[abi(embed_v0)]
    impl ArgentUserAccountImpl of super::IFutureArgentUserAccount<ContractState> {
        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: Signer,
            guardian: Option<Signer>,
        ) -> felt252 {
            let tx_info = get_tx_info();
            self
                .assert_valid_account_signature(
                    tx_info.transaction_hash, self.parse_account_signature(tx_info.signature),
                );
            VALIDATED
        }

        fn get_owner(self: @ContractState) -> felt252 {
            self._signer.read()
        }

        fn get_guardian(self: @ContractState) -> felt252 {
            self._guardian.read()
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls_and_signature(
            ref self: ContractState, calls: Span<Call>, execution_hash: felt252, mut signatures: Span<felt252>,
        ) {
            self.assert_valid_account_signature(execution_hash, self.parse_account_signature(signatures));
        }

        fn parse_account_signature(self: @ContractState, mut raw_signature: Span<felt252>) -> AccountSignature {
            let sigs_as_array: Array<SignerSignature> = full_deserialize(raw_signature)
                .expect('argent/invalid-signature-format');
            if sigs_as_array.len() == 1 {
                return AccountSignature { owner_signature: *sigs_as_array[0], guardian_signature: Option::None };
            } else if sigs_as_array.len() == 2 {
                return AccountSignature {
                    owner_signature: *sigs_as_array[0], guardian_signature: Option::Some(*sigs_as_array[1]),
                };
            }
            core::panic_with_felt252('argent/invalid-signature-length')
        }

        fn assert_valid_account_signature(self: @ContractState, hash: felt252, account_signature: AccountSignature) {
            assert(self.is_valid_owner_signature(hash, account_signature.owner_signature), 'argent/invalid-owner-sig');
            if let Option::Some(guardian_signature) = account_signature.guardian_signature {
                assert(self.is_valid_guardian_signature(hash, guardian_signature), 'argent/invalid-guardian-sig');
            } else {
                assert(self.get_guardian() != 0, 'argent/missing-guardian-sig');
            };
        }

        fn is_valid_owner_signature(self: @ContractState, hash: felt252, signer_signature: SignerSignature) -> bool {
            if self._signer.read() != signer_signature.signer().storage_value().stored_value {
                return false;
            }
            return signer_signature.is_valid_signature(hash);
        }

        fn is_valid_guardian_signature(self: @ContractState, hash: felt252, signer_signature: SignerSignature) -> bool {
            if self._guardian.read() != signer_signature.signer().storage_value().stored_value {
                return false;
            }
            return signer_signature.is_valid_signature(hash);
        }
    }
}
