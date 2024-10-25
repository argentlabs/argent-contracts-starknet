/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live
/// environment. It is solely for testing, educational, or demonstration purposes. Please refrain from relying on the
/// functionality of this contract for any production. 🚨
use argent::account::interface::{IAccount, IArgentAccount, Version};
use argent::signer::{
    signer_signature::{
        Signer, SignerStorageValue, SignerType, StarknetSigner, StarknetSignature, SignerTrait, SignerStorageTrait,
        SignerSignature, SignerSignatureTrait, starknet_signer_from_pubkey
    }
};

#[starknet::contract(account)]
mod MockFutureArgentAccount {
    use argent::account::interface::{IAccount, IArgentAccount, Version};
    use argent::introspection::src5::src5_component;

    use argent::signer::{
        signer_signature::{
            Signer, SignerStorageValue, SignerType, StarknetSigner, StarknetSignature, SignerTrait, SignerStorageTrait,
            SignerSignature, SignerSignatureTrait, starknet_signer_from_pubkey
        }
    };
    use argent::upgrade::{upgrade::upgrade_component, interface::IUpgradableCallback};
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_self}, calls::execute_multicall, serialization::full_deserialize,
    };
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use hash::HashStateTrait;
    use pedersen::PedersenTrait;
    use starknet::{
        ClassHash, get_block_timestamp, get_contract_address, VALIDATED, replace_class_syscall, account::Call,
        SyscallResultTrait, get_tx_info, get_execution_info, syscalls::storage_read_syscall,
        storage_access::{storage_address_from_base_and_offset, storage_base_address_from_felt252, storage_write_syscall}
    };
    use super::{IFutureArgentUserAccount, IFutureArgentUserAccountDispatcher, IFutureArgentUserAccountDispatcherTrait};

    const NAME: felt252 = 'ArgentAccount';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 5;
    const VERSION_PATCH: u8 = 0;
    const VERSION_COMPAT: felt252 = '0.5.0';

    // Introspection
    #[abi(embed_v0)]
    impl SRC5 = src5_component::SRC5Impl<ContractState>;
    component!(path: src5_component, storage: src5, event: SRC5Events);
    // Upgrade
    #[abi(embed_v0)]
    impl Upgradable = upgrade_component::UpgradableImpl<ContractState>;
    impl UpgradableInternal = upgrade_component::UpgradableInternalImpl<ContractState>;
    component!(path: upgrade_component, storage: upgrade, event: UpgradeEvents);

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

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            execute_multicall(calls.span())
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            if self.is_valid_span_signature(hash, self.parse_signature_array(signature.span())) {
                VALIDATED
            } else {
                0
            }
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        // Called when coming from account 0.4.0+
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            assert_only_self();
            let current_version = IFutureArgentUserAccountDispatcher { contract_address: get_contract_address() }
                .get_version();
            assert(current_version.major == 0 && current_version.minor >= 4, 'argent/invalid-from-version');
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
            guardian: Option<Signer>
        ) -> felt252 {
            let tx_info = get_tx_info();
            self.assert_valid_span_signature(tx_info.transaction_hash, self.parse_signature_array(tx_info.signature));
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
            self.assert_valid_span_signature(execution_hash, self.parse_signature_array(signatures));
        }

        fn parse_signature_array(self: @ContractState, mut signatures: Span<felt252>) -> Array<SignerSignature> {
            full_deserialize(signatures).expect('argent/invalid-signature-format')
        }

        fn is_valid_span_signature(
            self: @ContractState, hash: felt252, signer_signatures: Array<SignerSignature>
        ) -> bool {
            if self._guardian.read() == 0 {
                assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                self.is_valid_owner_signature(hash, *signer_signatures.at(0))
            } else {
                assert(signer_signatures.len() == 2, 'argent/invalid-signature-length');
                self.is_valid_owner_signature(hash, *signer_signatures.at(0))
                    && self.is_valid_guardian_signature(hash, *signer_signatures.at(1))
            }
        }

        fn assert_valid_span_signature(self: @ContractState, hash: felt252, signer_signatures: Array<SignerSignature>) {
            if self._guardian.read() == 0 {
                assert(signer_signatures.len() == 1, 'argent/invalid-signature-length');
                assert(self.is_valid_owner_signature(hash, *signer_signatures.at(0)), 'argent/invalid-owner-sig');
            } else {
                assert(signer_signatures.len() == 2, 'argent/invalid-signature-length');
                assert(self.is_valid_owner_signature(hash, *signer_signatures.at(0)), 'argent/invalid-owner-sig');
                assert(self.is_valid_guardian_signature(hash, *signer_signatures.at(1)), 'argent/invalid-guardian-sig');
            }
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

#[starknet::interface]
trait IFutureArgentUserAccount<TContractState> {
    fn __validate_deploy__(
        self: @TContractState,
        class_hash: felt252,
        contract_address_salt: felt252,
        owner: Signer,
        guardian: Option<Signer>
    ) -> felt252;
    fn get_owner(self: @TContractState) -> felt252;
    fn get_guardian(self: @TContractState) -> felt252;

    fn get_name(self: @TContractState) -> felt252;
    fn get_version(self: @TContractState) -> Version;
}

