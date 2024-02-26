const SESSION_MAGIC: felt252 = 'session-token';


#[starknet::interface]
trait ISessionable<TContractState> {
    fn revoke_session(ref self: TContractState, session_hash: felt252);
    fn is_session_revoked(self: @TContractState, session_hash: felt252) -> bool;
}

#[starknet::component]
mod session_component {
    use alexandria_merkle_tree::merkle_tree::{
        Hasher, MerkleTree, MerkleTreeImpl, poseidon::PoseidonHasherImpl, MerkleTreeTrait,
    };
    use argent::account::interface::{IAccount, IArgentUserAccount};
    use argent::session::{
        session::ISessionable,
        session_structs::{SessionToken, Session, IOffchainMessageHash, IStructHash, IMerkleLeafHash},
    };
    use argent::signer::signer_signature::{SignerSignatureTrait};
    use argent::utils::{asserts::{assert_no_self_call, assert_only_self}, serialization::full_deserialize};

    use ecdsa::check_ecdsa_signature;
    use poseidon::{hades_permutation};
    use starknet::{account::Call, get_contract_address, VALIDATED, get_block_timestamp};


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
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +IArgentUserAccount<TContractState>,
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
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +IArgentUserAccount<TContractState>,
    > of InternalTrait<TContractState> {
        fn assert_valid_session(
            self: @ComponentState<TContractState>,
            calls: Span<Call>,
            transaction_hash: felt252,
            signature: Span<felt252>,
            is_from_outside: bool,
        ) {
            let state = self.get_contract();
            let account_address = get_contract_address();

            assert_no_self_call(calls, account_address);
            assert(*signature[0] == super::SESSION_MAGIC, 'session/invalid-magic-value');

            let token: SessionToken = full_deserialize(signature.slice(1, signature.len() - 1))
                .expect('session/invalid-calldata');

            let token_session_hash = token.session.get_message_hash();

            assert(!self.revoked_session.read(token_session_hash), 'session/revoked');

            // timestamp check
            assert(token.session.expires_at >= get_block_timestamp(), 'session/expired');

            assert(
                state.is_valid_signature(token_session_hash, token.session_authorisation.snapshot.clone()) == VALIDATED,
                'session/invalid-account-sig'
            );

            let (message_hash, _, _) = hades_permutation(transaction_hash, token_session_hash, 2);

            // checks that the session key the user signed is the same key that signed the session
            let session_guid_from_sig = token.session_signature.signer_into_guid().expect('session/empty-session-key');
            assert(token.session.session_key_guid == session_guid_from_sig, 'session/session-key-mismatch');
            assert(token.session_signature.is_valid_signature(message_hash), 'session/invalid-session-sig');

            // checks that its the account guardian that signed the session
            let guardian_guid = state.get_guardian();
            let backend_guid_from_sig = token.backend_signature.signer_into_guid().expect('session/empty-backend-key');
            assert(backend_guid_from_sig == guardian_guid, 'session/guardian-key-mismatch');
            assert(token.backend_signature.is_valid_signature(message_hash), 'session/invalid-backend-sig');

            // TODO: possibly add guardian backup check

            assert_valid_session_calls(token, calls);
        }
    }

    fn assert_valid_session_calls(token: SessionToken, mut calls: Span<Call>) {
        assert(token.proofs.len() == calls.len(), 'unaligned-proofs');
        let merkle_root = token.session.allowed_methods_root;
        let mut merkle_tree: MerkleTree<Hasher> = MerkleTreeImpl::<_, PoseidonHasherImpl>::new();
        let mut proofs = token.proofs;
        loop {
            match calls.pop_front() {
                Option::Some(call) => {
                    let leaf = call.get_merkle_leaf();
                    let proof = proofs.pop_front().expect('session/proof-empty');
                    let is_valid = merkle_tree.verify(merkle_root, leaf, *proof);
                    assert(is_valid, 'session/invalid-call');
                },
                Option::None => { break; },
            };
        }
    }
}
