use starknet::{account::Call};

#[starknet::interface]
trait ISessionable<TContractState> {
    fn revoke_session(ref self: TContractState, session_key: felt252);
    fn assert_valid_session(
        ref self: TContractState, calls: Span<Call>, execution_hash: felt252, signature: Span<felt252>
    );
}

#[starknet::component]
mod sessionable {
    use argent::common::account::IAccount;
    use argent::common::asserts::{assert_no_self_call, assert_only_self};
    use argent::session::session_account::IGenericArgentAccount;
    use argent::session::session_structs::{SessionToken, IOffchainMessageHash, IStructHash};
    use ecdsa::check_ecdsa_signature;
    use hash::LegacyHash;
    use starknet::{account::Call, get_execution_info, VALIDATED};

    use alexandria_merkle_tree::merkle_tree::{MerkleTree, MerkleTreeTrait, Hasher};


    #[storage]
    struct Storage {
        revoked_session: LegacyMap<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SessionRevoked: SessionRevoked
    }

    #[derive(Drop, starknet::Event)]
    struct SessionRevoked {
        session_key: felt252,
    }

    #[embeddable_as(SessionableImpl)]
    impl Sessionable<
        TContractState,
        +HasComponent<TContractState>,
        +IAccount<TContractState>,
        +IGenericArgentAccount<TContractState>,
    > of super::ISessionable<ComponentState<TContractState>> {
        fn revoke_session(ref self: ComponentState<TContractState>, session_key: felt252) {
            assert_only_self();
            self.emit(SessionRevoked { session_key });
            self.revoked_session.write(session_key, true);
        }

        fn assert_valid_session(
            ref self: ComponentState<TContractState>,
            calls: Span<Call>,
            execution_hash: felt252,
            signature: Span<felt252>,
        ) {
            let state = self.get_contract();
            let execution_info = get_execution_info().unbox();
            let account_address = execution_info.contract_address;
            let tx_info = execution_info.tx_info.unbox();

            assert_no_self_call(calls, account_address);
            let mut serialized = signature.slice(1, signature.len() - 1);
            let token: SessionToken = Serde::deserialize(ref serialized).expect('argent/invalid-calldata');
            assert(serialized.is_empty(), 'excess-session-data');

            assert(!self.revoked_session.read(token.session.session_key), 'session-revoked');

            assert(
                state
                    .is_valid_signature(
                        token.session.get_message_hash(), token.owner_signature.snapshot.clone()
                    ) == VALIDATED,
                'invalid-owner-sig'
            );

            let message_hash = LegacyHash::hash(tx_info.transaction_hash, token.session.get_message_hash());

            assert(
                is_valid_signature_generic(message_hash, token.session.session_key, token.session_signature),
                'invalid-session-sig'
            );

            assert(
                is_valid_signature_generic(message_hash, state.get_guardian(), token.backend_signature),
                'invalid-guardian-sig'
            );
        }
    }

    fn is_valid_signature_generic(hash: felt252, signer: felt252, signature: Span<felt252>) -> bool {
        if signature.len() != 2 {
            return false;
        }
        let signature_r = *signature[0];
        let signature_s = *signature[1];
        check_ecdsa_signature(hash, signer, signature_r, signature_s)
    }

    
    // fn assert_valid_session_calls(
    //         token: SessionToken, mut calls: Span<Call>
    //     ) {
    //         assert(token.proofs.len() == calls.len(), 'unaligned-proofs');
    //         let merkle_root = token.session.allowed_methods_root;
    //         let mut index = 0;
    //         loop {
    //             match calls.pop_front() {
    //                 Option::Some(call) => {
    //                         let mut merkle_init: MerkleTree<Hasher> = MerkleTreeTrait::new();
    //                         let leaf = call.get_merkle_leaf();
    //                         let proof = *token.proofs[index];
    //                         let is_valid = merkle_init.verify(merkle_root, leaf, proof);
    //                         assert(is_valid, 'invalid-session-call');
    //                     }
    //                     index += 1;
    //                 },
    //                 Option::None => {
    //                     break;
    //                 },
    //             };
    //         }
}
