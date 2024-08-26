/// @dev 🚨 This smart contract is a mock implementation and is not meant for actual deployment or use in any live environment. It is solely for testing, educational, or demonstration purposes. Any interactions with this contract will not have real-world consequences or effects on blockchain networks. Please refrain from relying on the functionality of this contract for any production. 🚨
#[starknet::contract(account)]
mod MockFutureArgentMultisig {
    use argent::account::interface::{
        IAccount, IArgentAccount, IArgentAccountDispatcher, IArgentAccountDispatcherTrait, Version
    };
    use argent::external_recovery::external_recovery::IExternalRecoveryCallback;
    use argent::introspection::src5::src5_component;
    use argent::multisig::{multisig::multisig_component};

    use argent::signer::{signer_signature::{Signer, SignerTrait, SignerSignature, SignerSignatureTrait}};
    use argent::signer_storage::{
        interface::ISignerList, signer_list::{signer_list_component, signer_list_component::SignerListInternalImpl}
    };
    use argent::upgrade::{upgrade::upgrade_component, interface::{IUpgradableCallback, IUpgradableCallbackOld}};
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_protocol, assert_only_self,}, calls::execute_multicall,
        serialization::full_deserialize,
    };
    use core::array::ArrayTrait;
    use core::result::ResultTrait;
    use starknet::{get_tx_info, get_contract_address, VALIDATED, ClassHash, account::Call};

    const NAME: felt252 = 'ArgentMultisig';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 3;
    const VERSION_PATCH: u8 = 0;

    // Signer storage
    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    impl SignerListInternal = signer_list_component::SignerListInternalImpl<ContractState>;
    // Multisig management
    component!(path: multisig_component, storage: multisig, event: MultisigEvents);
    #[abi(embed_v0)]
    impl Multisig = multisig_component::MultisigImpl<ContractState>;
    impl MultisigInternal = multisig_component::MultisigInternalImpl<ContractState>;
    // Introspection
    component!(path: src5_component, storage: src5, event: SRC5Events);
    #[abi(embed_v0)]
    impl SRC5 = src5_component::SRC5Impl<ContractState>;
    // Upgrade
    #[abi(embed_v0)]
    impl Upgradable = upgrade_component::UpgradableImpl<ContractState>;
    component!(path: upgrade_component, storage: upgrade, event: UpgradeEvents);
    impl UpgradableInternal = upgrade_component::UpgradableInternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_list: signer_list_component::Storage,
        #[substorage(v0)]
        multisig: multisig_component::Storage,
        #[substorage(v0)]
        src5: src5_component::Storage,
        #[substorage(v0)]
        upgrade: upgrade_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SignerListEvents: signer_list_component::Event,
        #[flat]
        MultisigEvents: multisig_component::Event,
        #[flat]
        SRC5Events: src5_component::Event,
        #[flat]
        UpgradeEvents: upgrade_component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, new_threshold: usize, signers: Array<Signer>) {
        self.multisig.initialize(new_threshold, signers);
    }

    #[abi(embed_v0)]
    impl AccountImpl of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            let tx_info = get_tx_info().unbox();
            self.assert_valid_signatures(tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            execute_multicall(calls.span())
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            if self
                .multisig
                .is_valid_signature_with_threshold(
                    hash: hash,
                    threshold: self.multisig.threshold.read(),
                    signer_signatures: parse_signature_array(signature.span())
                ) {
                VALIDATED
            } else {
                0
            }
        }
    }

    #[abi(embed_v0)]
    impl ArgentAccountImpl of IArgentAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            panic_with_felt252('argent/declare-not-available') // Not implemented yet
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            new_threshold: usize,
            signers: Array<Signer>
        ) -> felt252 {
            panic_with_felt252('argent/deploy-not-available')
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackOldImpl of IUpgradableCallbackOld<ContractState> {
        // Called when coming from account < 0.2.0
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            panic_with_felt252('argent/no-direct-upgrade');
            array![]
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableCallbackImpl of IUpgradableCallback<ContractState> {
        // Called when coming from account 0.2.0+
        fn perform_upgrade(ref self: ContractState, new_implementation: ClassHash, data: Span<felt252>) {
            assert_only_self();
            let current_version = IArgentAccountDispatcher { contract_address: get_contract_address() }.get_version();
            assert(current_version.major == 0 && current_version.minor == 2, 'argent/invalid-from-version');
            assert(data.len() == 0, 'argent/unexpected-data');
            self.upgrade.complete_upgrade(new_implementation);
            self.multisig.assert_valid_storage();
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_signatures(self: @ContractState, execution_hash: felt252, signature: Span<felt252>) {
            let valid = self
                .multisig
                .is_valid_signature_with_threshold(
                    hash: execution_hash,
                    threshold: self.multisig.threshold.read(),
                    signer_signatures: parse_signature_array(signature)
                );
            assert(valid, 'argent/invalid-signature');
        }
    }

    fn parse_signature_array(mut raw_signature: Span<felt252>) -> Array<SignerSignature> {
        full_deserialize(raw_signature).expect('argent/invalid-signature-format')
    }
}

