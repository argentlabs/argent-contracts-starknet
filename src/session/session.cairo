#[starknet::interface]
trait ISessionable<TContractState> {
    fn revoke_session(ref self: TContractState, session_key: felt252);
    fn is_session_revoked(self: @TContractState, session_key: felt252);
}

#[starknet::component]
mod session_component {
    use alexandria_merkle_tree::merkle_tree::{Hasher, MerkleTree, pedersen::PedersenHasherImpl, MerkleTreeTrait,};
    use argent::account::interface::IArgentAccount;
    use argent::common::account::IAccount;
    use argent::common::asserts::{assert_no_self_call, assert_only_self};
    use argent::session::session::ISessionable;
    use argent::session::session_structs::{
        SessionToken, StarknetSignature, Session, IOffchainMessageHash, IStructHash, IMerkleLeafHash
    };
    use core::clone::Clone;
    use ecdsa::check_ecdsa_signature;
    use hash::LegacyHash;
    use starknet::{account::Call, get_contract_address, VALIDATED};


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
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +IArgentAccount<TContractState>,
    > of super::ISessionable<ComponentState<TContractState>> {
        fn revoke_session(ref self: ComponentState<TContractState>, session_key: felt252) {
            assert_only_self();
            self.emit(SessionRevoked { session_key });
            self.revoked_session.write(session_key, true);
        }

        fn is_session_revoked(self: @ComponentState<TContractState>, session_key: felt252) {
            self.revoked_session.read(session_key);
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +IArgentAccount<TContractState>,
    > of InternalTrait<TContractState> {
        fn assert_valid_session(
            self: @ComponentState<TContractState>,
            calls: Span<Call>,
            transaction_hash: felt252,
            signature: Span<felt252>,
        ) {
            let state = self.get_contract();
            let account_address = get_contract_address();

            assert_no_self_call(calls, account_address);
            let mut serialized = signature.slice(1, signature.len() - 1);
            let token: SessionToken = Serde::deserialize(ref serialized).expect('argent/invalid-calldata');
            assert(serialized.is_empty(), 'excess-session-data');

            assert(!self.revoked_session.read(token.session.session_key), 'session-revoked');

            assert(
                state
                    .is_valid_signature(
                        token.session.get_message_hash(), token.account_signature.snapshot.clone()
                    ) == VALIDATED,
                'invalid-account-sig'
            );

            let message_hash = LegacyHash::hash(transaction_hash, token.session.get_message_hash());

            assert(
                is_valid_signature_generic(message_hash, token.session.session_key, token.session_signature),
                'invalid-session-sig'
            );

            assert(
                is_valid_signature_generic(message_hash, token.session.guardian_key, token.backend_signature),
                'invalid-guardian-sig'
            );

            if state.get_guardian_backup() != 0 {
                assert(
                    !is_valid_signature_generic(transaction_hash, state.get_guardian_backup(), token.backend_signature),
                    'invalid-sig-from-backup'
                );
            }
            assert_valid_session_calls(token, calls);
        }
    }

    #[inline(always)]
    fn is_valid_signature_generic(hash: felt252, signer: felt252, signature: StarknetSignature) -> bool {
        check_ecdsa_signature(hash, signer, signature.r, signature.s)
    }

    fn assert_valid_session_calls(token: SessionToken, mut calls: Span<Call>) {
        assert(token.proofs.len() == calls.len(), 'unaligned-proofs');
        let merkle_root = token.session.allowed_methods_root;
        let mut index = 0;
        let mut merkle_init: MerkleTree<Hasher> = MerkleTreeTrait::new();
        loop {
            match calls.pop_front() {
                Option::Some(call) => {
                    let leaf = call.get_merkle_leaf();
                    let proof = *token.proofs[index];
                    let is_valid = merkle_init.verify(merkle_root, leaf, proof);
                    assert(is_valid, 'invalid-session-call');
                    index += 1;
                },
                Option::None => { break; },
            };
        }
    }
}
