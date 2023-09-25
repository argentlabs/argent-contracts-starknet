trait ISessionAccount<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate_deploy__(
        self: @TContractState, class_hash: felt252, contract_address_salt: felt252, owner: felt252
    ) -> felt252;
    fn revoke_session(ref self: TContractState, public_key: felt252);
    fn get_owner(self: @TContractState) -> felt252;
}

#[starknet::contract]
mod HybridSessionAccount {
    use ecdsa::check_ecdsa_signature;

    use starknet::{
        class_hash_const, ContractAddress, get_block_timestamp, get_caller_address,
        get_execution_info, get_contract_address, get_tx_info, VALIDATED, account::Call
    };
    use argent::common::asserts::{assert_caller_is_null, assert_no_self_call, assert_only_self};
    use argent::common::calls::execute_multicall;
    use argent::common::account::{IAccount, ERC165_ACCOUNT_INTERFACE_ID};

    #[storage]
    struct Storage {
        _signer: felt252,
        _guardian: felt252,
        revoked_session: LegacyMap<felt252, bool>,
    }

    const SESSION_MAGIC: felt252 = 'session-token';

    #[constructor]
    fn constructor(ref self: ContractState, owner: felt252) {
        assert(owner != 0, 'argent/null-owner');

        self._signer.write(owner);
    }

    #[external(v0)]
    impl Account of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            assert_caller_is_null();
            let tx_info = get_tx_info().unbox();
            if tx_info.signature.at(0) == @SESSION_MAGIC {
                self
                    .assert_valid_session_token(
                        calls.span(), tx_info.transaction_hash, tx_info.signature,
                    );
            } else {
                self
                    .assert_valid_calls_and_signature(
                        calls.span(), tx_info.transaction_hash, tx_info.signature,
                    );
            };
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert_caller_is_null();
            let tx_info = get_tx_info().unbox();
            let signature = tx_info.signature;
            return execute_multicall(calls.span());
        }

        fn is_valid_signature(
            self: @ContractState, hash: felt252, signature: Array<felt252>
        ) -> felt252 {
            if self.is_valid_owner_signature(hash, signature.span()) {
                VALIDATED
            } else {
                0
            }
        }
    }

    #[external(v0)]
    impl SessionAccount of super::ISessionAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let tx_info = get_tx_info().unbox();
            self.is_valid_owner_signature(tx_info.transaction_hash, tx_info.signature);
            VALIDATED
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: felt252,
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            let is_valid = self
                .is_valid_owner_signature(tx_info.transaction_hash, tx_info.signature);
            assert(is_valid, 'invalid-owner-signature');
            VALIDATED
        }

        fn revoke_session(ref self: ContractState, public_key: felt252) {
            assert_only_self();
            self.revoked_session.write(public_key, true);
        }

        fn get_owner(self: @ContractState) -> felt252 {
            self._signer.read()
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls_and_signature(
            ref self: ContractState,
            calls: Span<Call>,
            execution_hash: felt252,
            signature: Span<felt252>,
        ) {
            let execution_info = get_execution_info().unbox();
            let account_address = execution_info.contract_address;
            let tx_info = execution_info.tx_info.unbox();
            if calls.len() > 1 {
                assert_no_self_call(calls, account_address);
            }
            assert(
                self.is_valid_owner_signature(execution_hash, signature), 'invalid-owner-signature'
            );
        }

        fn assert_valid_session_token(
            ref self: ContractState,
            calls: Span<Call>,
            execution_hash: felt252,
            signature: Span<felt252>,
        ) {
            let execution_info = get_execution_info().unbox();
            let account_address = execution_info.contract_address;
            let tx_info = execution_info.tx_info.unbox();

            assert_no_self_call(calls, account_address);
            let mut serialized = signature.slice(1, signature.len() - 1);

            // assert(
            //     self.is_valid_owner_signature(session.get_message_hash(), owner_signature),
            //     'invalid-owner-signature'
            // );
            // assert(
            //     self
            //         .is_valid_session_signature(
            //             tx_info.transaction_hash, session.public_key, session_signature
            //         ),
            //     'invalid-session-signature'
            // );
        }

        fn is_valid_owner_signature(
            self: @ContractState, hash: felt252, signature: Span<felt252>
        ) -> bool {
            if signature.len() != 2 {
                return false;
            }
            let signature_r = *signature[0];
            let signature_s = *signature[1];
            check_ecdsa_signature(hash, self._signer.read(), signature_r, signature_s)
        }

        fn is_valid_session_signature(
            self: @ContractState,
            message_hash: felt252,
            public_key: felt252,
            signature: Span<felt252>
        ) -> bool {
            if signature.len() != 2 {
                return false;
            }
            let signature_r = *signature[0];
            let signature_s = *signature[1];
            check_ecdsa_signature(message_hash, public_key, signature_r, signature_s)
        }

}
}
