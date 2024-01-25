#[starknet::contract]
mod ArgentGenericAccount {
    use argent::common::signer_list::signer_list_component::InternalTrait;
    use argent::common::{
        account::{
            IAccount, ERC165_ACCOUNT_INTERFACE_ID, ERC165_ACCOUNT_INTERFACE_ID_OLD_1, ERC165_ACCOUNT_INTERFACE_ID_OLD_2
        },
        asserts::{assert_no_self_call, assert_only_protocol, assert_only_self,}, calls::execute_multicall,
        version::Version,
        erc165::{
            IErc165, IErc165LibraryDispatcher, IErc165DispatcherTrait, ERC165_IERC165_INTERFACE_ID,
            ERC165_IERC165_INTERFACE_ID_OLD,
        },
        outside_execution::{
            IOutsideExecutionCallback, ERC165_OUTSIDE_EXECUTION_INTERFACE_ID, outside_execution_component,
        },
        upgrade::{IUpgradeable, do_upgrade},
        signer_signature::{Signer, IntoGuid, SignerSignature, SignerSignatureTrait}, interface::IArgentMultisig,
        serialization::full_deserialize,
        transaction_version::{
            assert_correct_invoke_version, assert_no_unsupported_v3_fields, assert_correct_deploy_account_version
        },
        signer_list::signer_list_component
    };
    use argent::generic::{interface::{IRecoveryAccount}, recovery::{EscapeStatus, Escape, EscapeEnabled}};
    use core::array::ArrayTrait;
    use core::result::ResultTrait;
    use starknet::{
        get_tx_info, get_contract_address, VALIDATED, syscalls::replace_class_syscall, ClassHash, get_block_timestamp,
        get_caller_address, account::Call
    };

    const NAME: felt252 = 'ArgentGenericAccount';
    const VERSION_MAJOR: u8 = 0;
    const VERSION_MINOR: u8 = 0;
    const VERSION_PATCH: u8 = 1;
    /// Too many owners could make the multisig unable to process transactions if we reach a limit
    const MAX_SIGNERS_COUNT: usize = 32;

    component!(path: outside_execution_component, storage: execute_from_outside, event: ExecuteFromOutsideEvents);
    #[abi(embed_v0)]
    impl ExecuteFromOutside = outside_execution_component::OutsideExecutionImpl<ContractState>;

    impl OutsideExecutionCallbackImpl of IOutsideExecutionCallback<ContractState> {
        #[inline(always)]
        fn execute_from_outside_callback(
            ref self: ContractState, calls: Span<Call>, outside_execution_hash: felt252, signature: Span<felt252>,
        ) -> Array<Span<felt252>> {
            // validate calls
            self.assert_valid_calls(calls);
            // validate signatures
            self.assert_valid_signatures(calls, outside_execution_hash, signature);

            let retdata = execute_multicall(calls);
            self.emit(TransactionExecuted { hash: outside_execution_hash, response: retdata.span() });
            retdata
        }
    }

    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    impl SignerList = signer_list_component::Internal<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        execute_from_outside: outside_execution_component::Storage,
        #[substorage(v0)]
        signer_list: signer_list_component::Storage,
        threshold: usize,
        escape_enabled: EscapeEnabled,
        escape: Escape,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ExecuteFromOutsideEvents: outside_execution_component::Event,
        SignerListEvents: signer_list_component::Event,
        ThresholdUpdated: ThresholdUpdated,
        TransactionExecuted: TransactionExecuted,
        AccountUpgraded: AccountUpgraded,
        OwnerAdded: OwnerAdded,
        OwnerRemoved: OwnerRemoved,
        EscapeSignerTriggered: EscapeSignerTriggered,
        SignerEscaped: SignerEscaped,
        SignerLinked: SignerLinked
    }

    /// @notice Emitted when the multisig threshold changes
    /// @param new_threshold New threshold
    #[derive(Drop, starknet::Event)]
    struct ThresholdUpdated {
        new_threshold: usize,
    }

    /// @notice Emitted when the account executes a transaction
    /// @param hash The transaction hash
    /// @param response The data returned by the methods called
    #[derive(Drop, starknet::Event)]
    struct TransactionExecuted {
        #[key]
        hash: felt252,
        response: Span<Span<felt252>>
    }

    /// @notice Emitted when the implementation of the account changes
    /// @param new_implementation The new implementation
    #[derive(Drop, starknet::Event)]
    struct AccountUpgraded {
        new_implementation: ClassHash
    }

    /// This event is part of an account discoverability standard, SNIP not yet created
    /// Emitted when an account owner is added, including when the account is created.
    #[derive(Drop, starknet::Event)]
    struct OwnerAdded {
        #[key]
        new_owner_guid: felt252,
    }

    /// This event is part of an account discoverability standard, SNIP not yet created
    /// Emitted when an an account owner is removed
    #[derive(Drop, starknet::Event)]
    struct OwnerRemoved {
        #[key]
        removed_owner_guid: felt252,
    }

    /// @notice Guardian escape was triggered by the owner
    /// @param ready_at when the escape can be completed
    /// @param target_signer the escaped signer address
    /// @param new_signer the new signer address to be set after the security period
    #[derive(Drop, starknet::Event)]
    struct EscapeSignerTriggered {
        ready_at: u64,
        target_signer: felt252,
        new_signer: felt252
    }

    /// @notice Signer escape was completed and there is a new signer
    /// @param target_signer the escaped signer address
    /// @param new_signer the new signer address
    #[derive(Drop, starknet::Event)]
    struct SignerEscaped {
        target_signer: felt252,
        new_signer: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct SignerLinked {
        #[key]
        signer_guid: felt252,
        signer: Signer,
    }

    #[constructor]
    fn constructor(ref self: ContractState, new_threshold: usize, signers: Array<Signer>) {
        let new_signers_count = signers.len();
        assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

        let mut signers_span = signers.span();
        let mut last_signer = 0;
        loop {
            match signers_span.pop_front() {
                Option::Some(signer) => {
                    let signer_guid = (*signer).into_guid().expect('argent/invalid-signer-guid');
                    self.signer_list.add_signer(signer_to_add: signer_guid, last_signer: last_signer);
                    self.emit(OwnerAdded { new_owner_guid: signer_guid });
                    last_signer = signer_guid;
                },
                Option::None => { break; }
            }
        };

        self.threshold.write(new_threshold);
        self.emit(ThresholdUpdated { new_threshold });
    }

    #[external(v0)]
    impl Account of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            assert_only_protocol();
            let tx_info = get_tx_info().unbox();
            assert_correct_invoke_version(tx_info.version);
            assert_no_unsupported_v3_fields();

            self.assert_valid_calls(calls.span());
            self.assert_valid_signatures(calls.span(), tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert_only_protocol();
            let tx_info = get_tx_info().unbox();
            assert_correct_invoke_version(tx_info.version);

            // execute calls
            let retdata = execute_multicall(calls.span());
            // emit event
            let hash = tx_info.transaction_hash;
            let response = retdata.span();
            self.emit(TransactionExecuted { hash, response });
            retdata
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            let threshold = self.threshold.read();
            if self.is_valid_signature_with_conditions(hash, threshold, 0_felt252, signature.span()) {
                VALIDATED
            } else {
                0
            }
        }
    }

    #[external(v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        /// @dev Can be called by the account to upgrade the implementation
        fn upgrade(ref self: ContractState, new_implementation: ClassHash, calldata: Array<felt252>) -> Array<felt252> {
            assert_only_self();
            self.emit(AccountUpgraded { new_implementation });
            do_upgrade(new_implementation, calldata)
        }
        fn execute_after_upgrade(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            assert_only_self();

            // Check basic invariants
            assert_valid_threshold_and_signers_count(self.threshold.read(), self.signer_list.get_signers_len());

            assert(data.len() == 0, 'argent/unexpected-data');
            array![]
        }
    }

    #[external(v0)]
    impl ArgentMultisigImpl of IArgentMultisig<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            panic_with_felt252('argent/declare-not-available') // Not implemented yet
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            threshold: usize,
            signers: Array<Signer>
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            assert_correct_deploy_account_version(tx_info.version);
            assert_no_unsupported_v3_fields();

            let mut signature = tx_info.signature;
            let mut parsed_signatures: Array<SignerSignature> = full_deserialize(signature)
                .expect('argent/signature-not-empty');
            // only 1 valid signature is needed to deploy  
            assert(parsed_signatures.len() >= 1, 'argent/invalid-signature-length');
            let is_valid = self.is_valid_signer_signature(tx_info.transaction_hash, *parsed_signatures.at(0),);
            assert(is_valid, 'argent/invalid-signature');
            VALIDATED
        }

        fn change_threshold(ref self: ContractState, new_threshold: usize) {
            assert_only_self();
            assert(new_threshold != self.threshold.read(), 'argent/same-threshold');
            let new_signers_count = self.signer_list.get_signers_len();

            assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);
            self.threshold.write(new_threshold);
            self.emit(ThresholdUpdated { new_threshold });
        }

        fn add_signers(ref self: ContractState, new_threshold: usize, signers_to_add: Array<Signer>) {
            assert_only_self();
            let (signers_len, last_signer_guid) = self.signer_list.load();
            let previous_threshold = self.threshold.read();

            let new_signers_count = signers_len + signers_to_add.len();
            assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

            let mut signers_span = signers_to_add.span();
            let mut last_signer = last_signer_guid;
            loop {
                match signers_span.pop_front() {
                    Option::Some(signer) => {
                        let signer_guid = (*signer).into_guid().expect('argent/invalid-signer-guid');
                        self.signer_list.add_signer(signer_to_add: signer_guid, last_signer: last_signer);
                        self.emit(OwnerAdded { new_owner_guid: signer_guid });
                        last_signer = signer_guid;
                    },
                    Option::None => { break; }
                }
            };

            self.threshold.write(new_threshold);
            if previous_threshold != new_threshold {
                self.emit(ThresholdUpdated { new_threshold });
            }
        }

        fn remove_signers(ref self: ContractState, new_threshold: usize, signers_to_remove: Array<Signer>) {
            assert_only_self();
            let (signers_len, last_signer_guid) = self.signer_list.load();
            let previous_threshold = self.threshold.read();

            let new_signers_count = signers_len - signers_to_remove.len();
            assert_valid_threshold_and_signers_count(new_threshold, new_signers_count);

            let mut signers_span = signers_to_remove.span();
            let mut last_signer = last_signer_guid;
            loop {
                match signers_span.pop_front() {
                    Option::Some(signer_ref) => {
                        let signer_guid = (*signer_ref).into_guid().expect('argent/invalid-signer-guid');
                        last_signer = self
                            .signer_list
                            .remove_signer(signer_to_remove: signer_guid, last_signer: last_signer);
                        self.emit(OwnerRemoved { removed_owner_guid: signer_guid });
                    },
                    Option::None => { break; }
                }
            };

            self.threshold.write(new_threshold);
            if previous_threshold != new_threshold {
                self.emit(ThresholdUpdated { new_threshold });
            }
        }

        fn reorder_signers(ref self: ContractState, new_signer_order: Array<Signer>) {
            assert_only_self();
            let (signers_len, mut last_signer) = self.signer_list.load();
            assert(new_signer_order.len() == signers_len, 'argent/too-short');
            //remove all the signers of the list
            let mut new_signer_order_span = new_signer_order.span();
            let mut new_signer_order_guid = array![];
            loop {
                match new_signer_order_span.pop_front() {
                    Option::Some(signer) => {
                        let signer_guid = (*signer).into_guid().expect('argent/invalid-signer-guid');
                        new_signer_order_guid.append(signer_guid);
                        last_signer = self
                            .signer_list
                            .remove_signer(signer_to_remove: signer_guid, last_signer: last_signer);
                    },
                    Option::None => { break; }
                };
            };
            // add all the signers of the list
            self.signer_list.add_signers(signers_to_add: new_signer_order_guid.span(), last_signer: 0);
        }

        fn replace_signer(ref self: ContractState, signer_to_remove: Signer, signer_to_add: Signer) {
            assert_only_self();
            let (new_signers_count, last_signer) = self.signer_list.load();

            let signer_to_remove_guid = signer_to_remove.into_guid().expect('argent/invalid-signer-guid');
            let signer_to_add_guid = signer_to_add.into_guid().expect('argent/invalid-signer-guid');
            self
                .signer_list
                .replace_signer(
                    signer_to_remove: signer_to_remove_guid, signer_to_add: signer_to_add_guid, last_signer: last_signer
                );

            self.emit(OwnerRemoved { removed_owner_guid: signer_to_remove_guid });
            self.emit(OwnerAdded { new_owner_guid: signer_to_add_guid });
        }

        fn get_name(self: @ContractState) -> felt252 {
            NAME
        }

        /// Semantic version of this contract
        fn get_version(self: @ContractState) -> Version {
            Version { major: VERSION_MAJOR, minor: VERSION_MINOR, patch: VERSION_PATCH }
        }

        fn get_threshold(self: @ContractState) -> usize {
            self.threshold.read()
        }

        fn get_signers_guid(self: @ContractState) -> Array<felt252> {
            self.signer_list.get_signers()
        }

        fn is_signer(self: @ContractState, signer: Signer) -> bool {
            self.signer_list.is_signer(signer.into_guid().unwrap())
        }

        fn is_signer_guid(self: @ContractState, signer_guid: felt252) -> bool {
            self.signer_list.is_signer(signer_guid)
        }

        fn is_valid_signer_signature(self: @ContractState, hash: felt252, signer_signature: SignerSignature) -> bool {
            let is_signer = self.signer_list.is_signer(signer_signature.signer_into_guid().unwrap());
            assert(is_signer, 'argent/not-a-signer');
            signer_signature.is_valid_signature(hash)
        }
    }

    #[external(v0)]
    impl RecoveryAccountImpl of IRecoveryAccount<ContractState> {
        fn toggle_escape(ref self: ContractState, is_enabled: bool, security_period: u64, expiry_period: u64) {
            assert_only_self();
            // cannot toggle escape if there is an ongoing escape 
            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            let current_escaped_signer = current_escape.target_signer;
            assert(
                current_escaped_signer == 0 || current_escape_status == EscapeStatus::Expired, 'argent/ongoing-escape'
            );

            if (is_enabled) {
                assert(security_period != 0 && expiry_period != 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: 1, security_period, expiry_period });
            } else {
                assert(escape_config.is_enabled == 1, 'argent/escape-disabled');
                assert(security_period == 0 && expiry_period == 0, 'argent/invalid-escape-params');
                self.escape_enabled.write(EscapeEnabled { is_enabled: 0, security_period, expiry_period });
            }
        }

        fn trigger_escape_signer(ref self: ContractState, target_signer: Signer, new_signer: Signer) {
            assert_only_self();

            let target_signer_guid = target_signer.into_guid().expect('argent/invalid-signer-guid');
            let new_signer_guid = new_signer.into_guid().expect('argent/invalid-signer-guid');
            self.emit(SignerLinked { signer_guid: new_signer_guid, signer: new_signer });

            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            let current_escaped_signer = current_escape.target_signer;
            if (current_escaped_signer != 0 && current_escape_status == EscapeStatus::Ready) {
                // can only override an escape with a target signer of lower priority than the current one
                assert(
                    self.signer_list.is_signer_before(current_escaped_signer, target_signer_guid),
                    'argent/cannot-override-escape'
                );
            }
            let ready_at = get_block_timestamp() + escape_config.security_period;
            let escape = Escape { ready_at, target_signer: target_signer_guid, new_signer: new_signer_guid };
            self.escape.write(escape);
            self
                .emit(
                    EscapeSignerTriggered { ready_at, target_signer: target_signer_guid, new_signer: new_signer_guid }
                );
        }

        fn escape_signer(ref self: ContractState) {
            assert_only_self();

            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status == EscapeStatus::Ready, 'argent/invalid-escape');

            // replace signer 
            let (_, last_signer) = self.signer_list.load();
            self.signer_list.replace_signer(current_escape.target_signer, current_escape.new_signer, last_signer);
            self
                .emit(
                    SignerEscaped { target_signer: current_escape.target_signer, new_signer: current_escape.new_signer }
                );
            self.emit(OwnerRemoved { removed_owner_guid: current_escape.target_signer });
            self.emit(OwnerAdded { new_owner_guid: current_escape.new_signer });

            // clear escape
            self.escape.write(Escape { ready_at: 0, target_signer: 0, new_signer: 0 });
        }

        fn cancel_escape(ref self: ContractState) {
            assert_only_self();
            let current_escape = self.escape.read();
            let escape_config = self.escape_enabled.read();
            let current_escape_status = get_escape_status(current_escape.ready_at, escape_config.expiry_period);
            assert(current_escape_status != EscapeStatus::None, 'argent/invalid-escape');
            self.escape.write(Escape { ready_at: 0, target_signer: 0, new_signer: 0 });
        }
    }

    #[external(v0)]
    impl Erc165Impl of IErc165<ContractState> {
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            if interface_id == ERC165_IERC165_INTERFACE_ID {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID {
                true
            } else if interface_id == ERC165_OUTSIDE_EXECUTION_INTERFACE_ID {
                true
            } else if interface_id == ERC165_IERC165_INTERFACE_ID_OLD {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID_OLD_1 {
                true
            } else if interface_id == ERC165_ACCOUNT_INTERFACE_ID_OLD_2 {
                true
            } else {
                false
            }
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls(self: @ContractState, calls: Span<Call>) {
            let account_address = get_contract_address();
            if calls.len() == 1 {
                let call = calls.at(0);
                if *call.to == account_address {
                    // This should only be called after an upgrade, never directly
                    assert(*call.selector != selector!("execute_after_upgrade"), 'argent/forbidden-call');
                }
            } else {
                // Make sure no call is to the account. We don't have any good reason to perform many calls to the account in the same transactions
                // and this restriction will reduce the attack surface
                assert_no_self_call(calls, account_address);
            }
        }

        fn assert_valid_signatures(
            self: @ContractState, calls: Span<Call>, execution_hash: felt252, signature: Span<felt252>
        ) {
            // get threshold
            let threshold = self.threshold.read();
            let first_call = calls.at(0);
            if (*first_call.to == get_contract_address()) {
                if (*first_call.selector == selector!("trigger_escape_signer")) {
                    // check we can do recovery
                    let escape_enabled = self.escape_enabled.read();
                    assert(escape_enabled.is_enabled == 1 && threshold > 1, 'argent/recovery-unavailable');
                    // get escaped signer
                    let mut calldata: Span<felt252> = first_call.calldata.span();
                    let escaped_signer: Signer = Serde::deserialize(ref calldata).expect('argent/invalid-calldata');
                    let escaped_signer_guid = escaped_signer.into_guid().expect('argent/invalid-signer-guid');
                    // check it is a valid signer
                    let is_signer = self.signer_list.is_signer(escaped_signer_guid);
                    assert(is_signer, 'argent/escaped-not-signer');
                    // check signatures
                    let valid = self
                        .is_valid_signature_with_conditions(
                            execution_hash, threshold - 1, escaped_signer_guid, signature
                        );
                    assert(valid, 'argent/invalid-signature');
                    return;
                } else if (*first_call.selector == selector!("escape_signer")) {
                    // check we can do recovery
                    let escape_config = self.escape_enabled.read();
                    assert(escape_config.is_enabled == 1 && threshold > 1, 'argent/recovery-unavailable');
                    // get escaped signer
                    let escaped_signer_guid = (self.escape.read()).target_signer;
                    // check signatures
                    let valid = self
                        .is_valid_signature_with_conditions(
                            execution_hash, threshold - 1, escaped_signer_guid, signature
                        );
                    assert(valid, 'argent/invalid-signature');
                    return;
                }
            }

            let valid = self.is_valid_signature_with_conditions(execution_hash, threshold, 0_felt252, signature);
            assert(valid, 'argent/invalid-signature');
        }

        fn is_valid_signature_with_conditions(
            self: @ContractState,
            hash: felt252,
            expected_length: u32,
            excluded_signer: felt252,
            mut signature: Span<felt252>
        ) -> bool {
            let mut signer_signatures: Array<SignerSignature> = full_deserialize(signature)
                .expect('argent/signature-not-empty');
            assert(signer_signatures.len() == expected_length, 'argent/signature-invalid-length');

            let mut last_signer: u256 = 0;
            loop {
                match signer_signatures.pop_front() {
                    Option::Some(signer_sig) => {
                        let signer_guid = signer_sig.signer_into_guid().expect('argent/invalid-signer-guid');
                        assert(self.signer_list.is_signer(signer_guid), 'argent/not-a-signer');
                        assert(signer_guid != excluded_signer, 'argent/unauthorised_signer');
                        let signer_uint: u256 = signer_guid.into();
                        assert(signer_uint > last_signer, 'argent/signatures-not-sorted');
                        let is_valid = signer_sig.is_valid_signature(hash);
                        if !is_valid {
                            break false;
                        }
                        last_signer = signer_uint;
                    },
                    Option::None => { break true; }
                };
            }
        }
    }

    fn assert_valid_threshold_and_signers_count(threshold: usize, signers_len: usize) {
        assert(threshold != 0, 'argent/invalid-threshold');
        assert(signers_len != 0, 'argent/invalid-signers-len');
        assert(signers_len <= MAX_SIGNERS_COUNT, 'argent/invalid-signers-len');
        assert(threshold <= signers_len, 'argent/bad-threshold');
    }

    fn get_escape_status(escape_ready_at: u64, expiry_period: u64) -> EscapeStatus {
        if escape_ready_at == 0 {
            return EscapeStatus::None;
        }

        let block_timestamp = get_block_timestamp();
        if block_timestamp < escape_ready_at {
            return EscapeStatus::NotReady;
        }
        if escape_ready_at + expiry_period <= block_timestamp {
            return EscapeStatus::Expired;
        }

        EscapeStatus::Ready
    }
}
