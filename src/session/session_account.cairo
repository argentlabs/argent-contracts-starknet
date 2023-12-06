#[starknet::interface]
trait IGenericArgentAccount<TContractState> {
    fn __validate_declare__(self: @TContractState, class_hash: felt252) -> felt252;
    fn __validate_deploy__(
        self: @TContractState, class_hash: felt252, contract_address_salt: felt252, owner: felt252, guardian: felt252,
    ) -> felt252;
    fn get_guardian(self: @TContractState) -> felt252;
}

#[starknet::contract]
mod HybridSessionAccount {
    use argent::common::account::IAccount;
    use argent::common::asserts::{assert_caller_is_null, assert_no_self_call, assert_only_self};
    use argent::common::calls::execute_multicall;
    use argent::session::session::ISessionable;
    use argent::session::session::sessionable as session_component;
    use argent::session::session_structs::{Session, SessionToken, IOffchainMessageHash, IStructHash};
    use ecdsa::check_ecdsa_signature;
    use hash::LegacyHash;
    use starknet::{
        class_hash_const, ContractAddress, get_block_timestamp, get_caller_address, get_execution_info,
        get_contract_address, get_tx_info, VALIDATED, account::Call
    };

    component!(path: session_component, storage: sessionable, event: SessionableEvent);

    #[abi(embed_v0)]
    impl Sessionable = session_component::SessionableImpl<ContractState>;


    #[storage]
    struct Storage {
        owner: felt252,
        guardian: felt252,
        #[substorage(v0)]
        sessionable: session_component::Storage
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SessionableEvent: session_component::Event
    }

    const SESSION_MAGIC: felt252 = 'session-token';


    #[constructor]
    fn constructor(ref self: ContractState, owner: felt252, guardian: felt252) {
        assert(owner != 0, 'argent/null-owner');
        assert(guardian != 0, 'argent/null-guardian');
        self.owner.write(owner);
        self.guardian.write(guardian);
    }

    #[external(v0)]
    impl Account of IAccount<ContractState> {
        fn __validate__(ref self: ContractState, calls: Array<Call>) -> felt252 {
            assert_caller_is_null();
            let tx_info = get_tx_info().unbox();
            if *tx_info.signature[0] == SESSION_MAGIC {
                self.assert_valid_session(calls.span(), tx_info.transaction_hash, tx_info.signature);
            } else {
                self.assert_valid_calls_and_signature(calls.span(), tx_info.transaction_hash, tx_info.signature,);
            };
            VALIDATED
        }

        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            assert_caller_is_null();
            return execute_multicall(calls.span());
        }

        fn is_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) -> felt252 {
            if self.is_valid_signature_generic(hash, self.owner.read(), signature.span()) {
                VALIDATED
            } else {
                0
            }
        }
    }

    #[external(v0)]
    impl GenericArgentAccount of super::IGenericArgentAccount<ContractState> {
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            let tx_info = get_tx_info().unbox();
            self.is_valid_signature_generic(tx_info.transaction_hash, self.owner.read(), tx_info.signature);
            VALIDATED
        }

        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            contract_address_salt: felt252,
            owner: felt252,
            guardian: felt252,
        ) -> felt252 {
            let tx_info = get_tx_info().unbox();
            let is_valid = self
                .is_valid_signature_generic(tx_info.transaction_hash, self.owner.read(), tx_info.signature);
            assert(is_valid, 'invalid-owner-signature');
            VALIDATED
        }

        fn get_guardian(self: @ContractState) -> felt252 {
            self.guardian.read()
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn assert_valid_calls_and_signature(
            ref self: ContractState, calls: Span<Call>, execution_hash: felt252, signature: Span<felt252>,
        ) {
            let execution_info = get_execution_info().unbox();
            let account_address = execution_info.contract_address;
            let tx_info = execution_info.tx_info.unbox();
            if calls.len() > 1 {
                assert_no_self_call(calls, account_address);
            }
            assert(
                self.is_valid_signature_generic(execution_hash, self.owner.read(), signature), 'invalid-owner-signature'
            );
        }

        fn is_valid_signature_generic(
            self: @ContractState, hash: felt252, signer: felt252, signature: Span<felt252>
        ) -> bool {
            if signature.len() != 2 {
                return false;
            }
            let signature_r = *signature[0];
            let signature_s = *signature[1];
            check_ecdsa_signature(hash, signer, signature_r, signature_s)
        }
    }
}

