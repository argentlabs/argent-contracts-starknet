const SESSION_MAGIC: felt252 = 'session-token';


#[starknet::interface]
trait ISessionable<TContractState> {
    fn revoke_session(ref self: TContractState, session_hash: felt252);
    fn is_session_revoked(self: @TContractState, session_hash: felt252) -> bool;
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
        session_hash: felt252,
    }

    #[embeddable_as(SessionableImpl)]
    impl Sessionable<
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +IArgentAccount<TContractState>,
    > of super::ISessionable<ComponentState<TContractState>> {
        fn revoke_session(ref self: ComponentState<TContractState>, session_hash: felt252) {
            assert_only_self();
            assert(!self.revoked_session.read(session_hash), 'session/already-revoked');
            self.emit(SessionRevoked { session_hash });
            self.revoked_session.write(session_hash, true);
        }

        fn is_session_revoked(self: @ComponentState<TContractState>, session_hash: felt252) -> bool {
            self.revoked_session.read(session_hash)
        }
    }

    #[generate_trait]
    impl Internal<
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +IArgentAccount<TContractState>,
    > of InternalTrait<TContractState> {
        fn assert_valid_session(
            self: @ComponentState<TContractState>,
            calls: Span<Call>,
            transaction_hash: felt252,
            signature: Span<felt252>,
        ) {
            // TODO: add check to make sure v3 tx are only possible if the fee token in the session is STRK and same for ETH

            let state = self.get_contract();
            let account_address = get_contract_address();

            assert_no_self_call(calls, account_address);
            assert(*signature[0] == super::SESSION_MAGIC, 'session/invalid-sig-prefix');
            let mut serialized = signature.slice(1, signature.len() - 1);
            let token: SessionToken = Serde::deserialize(ref serialized).expect('session/invalid-calldata');
            assert(serialized.is_empty(), 'session/excess-data');

            let token_session_hash = token.session.get_message_hash();

            assert(!self.revoked_session.read(token_session_hash), 'session/revoked');

            // TODO: maybe use poseidon hash

            assert(
                state.is_valid_signature(token_session_hash, token.account_signature.snapshot.clone()) == VALIDATED,
                'session/invalid-account-sig'
            );

            let message_hash = LegacyHash::hash(transaction_hash, token_session_hash);

            assert(
                is_valid_signature_generic(message_hash, token.session.session_key, token.session_signature),
                'session/invalid-session-sig'
            );

            assert(
                is_valid_signature_generic(message_hash, token.session.guardian_key, token.backend_signature),
                'session/invalid-guardian-sig'
            );

            // TODO: possibly add guardian backup check

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
        let mut merkle_init: MerkleTree<Hasher> = MerkleTreeTrait::new();
        let mut proofs = token.proofs;
        loop {
            match calls.pop_front() {
                Option::Some(call) => {
                    let leaf = call.get_merkle_leaf();
                    let proof = proofs.pop_front().expect('session/proof-empty');
                    let is_valid = merkle_init.verify(merkle_root, leaf, *proof);
                    assert(is_valid, 'session/invalid-call');
                },
                Option::None => { break; },
            };
        }
    }
}
