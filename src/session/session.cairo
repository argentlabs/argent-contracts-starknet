#[starknet::component]
mod session_component {
    use alexandria_merkle_tree::merkle_tree::{
        Hasher, MerkleTree, MerkleTreeImpl, poseidon::PoseidonHasherImpl, MerkleTreeTrait,
    };
    use argent::account::interface::{IAccount, IArgentUserAccount};
    use argent::session::{
        session_hash::{OffChainMessageHashSessionRev1, MerkleLeafHash},
        interface::{ISessionable, SessionToken, Session, ISessionCallback},
    };
    use argent::signer::signer_signature::{SignerSignatureTrait, SignerTrait, SignerSignature};
    use argent::utils::{asserts::{assert_no_self_call, assert_only_self}, serialization::full_deserialize};
    use hash::{HashStateExTrait, HashStateTrait};
    use poseidon::PoseidonTrait;
    use starknet::{account::Call, get_contract_address, VALIDATED, get_block_timestamp};


    #[storage]
    struct Storage {
        /// A map of session hashes to a boolean indicating if the session has been revoked.
        revoked_session: LegacyMap<felt252, bool>,
        /// A map of (owner_guid, guardian_guid, session_hash) to a len of authorization signature
        valid_session_cache: LegacyMap<(felt252, felt252, felt252), u32>,
    }

    const SESSION_MAGIC: felt252 = 'session-token';

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SessionRevoked: SessionRevoked
    }

    #[derive(Drop, starknet::Event)]
    struct SessionRevoked {
        session_hash: felt252,
    }

    #[embeddable_as(SessionImpl)]
    impl Sessionable<
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +IArgentUserAccount<TContractState>,
    > of ISessionable<ComponentState<TContractState>> {
        fn revoke_session(ref self: ComponentState<TContractState>, session_hash: felt252) {
            assert_only_self();
            assert(!self.revoked_session.read(session_hash), 'session/already-revoked');
            self.emit(SessionRevoked { session_hash });
            self.revoked_session.write(session_hash, true);
        }

        #[inline(always)]
        fn is_session_revoked(self: @ComponentState<TContractState>, session_hash: felt252) -> bool {
            self.revoked_session.read(session_hash)
        }

        #[inline(always)]
        fn is_session_authorization_cached(self: @ComponentState<TContractState>, session_hash: felt252) -> bool {
            let state = self.get_contract();
            let guardian_guid = state.get_guardian_guid().expect('session/no-guardian');
            let owner_guid = state.get_owner_guid();
            self.valid_session_cache.read((owner_guid, guardian_guid, session_hash)).is_non_zero()
        }
    }

    #[generate_trait]
    impl Internal<
        TContractState,
        +HasComponent<TContractState>,
        +IAccount<TContractState>,
        +IArgentUserAccount<TContractState>,
        +ISessionCallback<TContractState>,
    > of InternalTrait<TContractState> {
        #[inline(always)]
        fn is_session(self: @ComponentState<TContractState>, signature: Span<felt252>) -> bool {
            match signature.get(0) {
                Option::Some(session_magic) => *session_magic.unbox() == SESSION_MAGIC,
                Option::None => false
            }
        }

        fn assert_valid_session(
            ref self: ComponentState<TContractState>,
            calls: Span<Call>,
            transaction_hash: felt252,
            signature: Span<felt252>,
        ) {
            let state = self.get_contract();
            let account_address = get_contract_address();

            assert_no_self_call(calls, account_address);
            assert(self.is_session(signature), 'session/invalid-magic-value');

            let token: SessionToken = full_deserialize(signature.slice(1, signature.len() - 1))
                .expect('session/invalid-calldata');

            let token_session_hash = token.session.get_message_hash_rev_1();

            assert(!self.revoked_session.read(token_session_hash), 'session/revoked');

            assert(token.session.expires_at >= get_block_timestamp(), 'session/expired');

            self.assert_valid_session_authorization(state, @token, token_session_hash);

            let message_hash = PoseidonTrait::new()
                .update_with(transaction_hash)
                .update_with(token_session_hash)
                .update_with(token.cache_authorization)
                .finalize();

            // checks that the session key the user signed is the same key that signed the session
            let session_guid_from_sig = token.session_signature.signer().into_guid();
            assert(token.session.session_key_guid == session_guid_from_sig, 'session/session-key-mismatch');
            assert(token.session_signature.is_valid_signature(message_hash), 'session/invalid-session-sig');

            // checks that its the account guardian that signed the session
            assert(state.is_guardian(token.guardian_signature.signer()), 'session/guardian-key-mismatch');
            assert(token.guardian_signature.is_valid_signature(message_hash), 'session/invalid-backend-sig');

            assert_valid_session_calls(@token, calls);
        }


        fn assert_valid_session_authorization(
            ref self: ComponentState<TContractState>,
            state: @TContractState,
            token: @SessionToken,
            session_hash: felt252,
        ) {
            let session_authorization = *token.session_authorization;
            let guardian_guid = state.get_guardian_guid().expect('session/no-guardian');
            if (*token.cache_authorization) {
                let owner_guid = state.get_owner_guid();
                let cached_sig_len = self.valid_session_cache.read((owner_guid, guardian_guid, session_hash));
                let authorization_len = session_authorization.len();
                if cached_sig_len != 0 {
                    // prevents a DoS attack where a user can send a large session authorization
                    assert(authorization_len <= cached_sig_len, 'session/invalid-auth-len');
                    return;
                } else {
                    assert(
                        state.session_verify_sig_callback(session_hash, session_authorization, guardian_guid),
                        'session/invalid-account-sig'
                    );
                    self.valid_session_cache.write((owner_guid, guardian_guid, session_hash), authorization_len);
                    return;
                }
            }

            assert(
                state.session_verify_sig_callback(session_hash, session_authorization, guardian_guid),
                'session/invalid-account-sig'
            );
        }
    }

    fn assert_valid_session_calls(token: @SessionToken, mut calls: Span<Call>) {
        assert((*token.proofs).len() == calls.len(), 'session/unaligned-proofs');
        let merkle_root = *token.session.allowed_methods_root;
        let mut merkle_tree: MerkleTree<Hasher> = MerkleTreeImpl::new();
        let mut proofs = *token.proofs;
        while let Option::Some(call) = calls
            .pop_front() {
                let leaf = call.get_merkle_leaf();
                let proof = proofs.pop_front().expect('session/proof-empty');
                let is_valid = merkle_tree.verify(merkle_root, leaf, *proof);
                assert(is_valid, 'session/invalid-call');
            };
    }
}
