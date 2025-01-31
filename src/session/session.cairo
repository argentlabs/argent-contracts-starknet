#[starknet::component]
mod session_component {
    use alexandria_merkle_tree::merkle_tree::{
        Hasher, MerkleTree, MerkleTreeImpl, MerkleTreeTrait, poseidon::PoseidonHasherImpl,
    };
    use argent::account::interface::IAccount;
    use argent::session::{
        interface::{ISessionCallback, ISessionable, Session, SessionToken},
        session_hash::{MerkleLeafHash, OffChainMessageHashSessionRev1},
    };
    use argent::signer::signer_signature::{Signer, SignerSignatureTrait, SignerTrait};
    use argent::utils::{
        asserts::{assert_no_self_call, assert_only_self}, serialization::full_deserialize,
        transaction_version::is_estimate_transaction,
    };
    use hash::{HashStateExTrait, HashStateTrait};
    use poseidon::PoseidonTrait;
    use starknet::{account::Call, get_block_timestamp, get_contract_address, storage::Map};

    #[storage]
    struct Storage {
        /// A map of session hashes to a boolean indicating if the session has been revoked.
        revoked_session: Map<felt252, bool>,
        /// A map of (owner_guid, guardian_guid, session_hash) to a len of authorization signature
        valid_session_cache: Map<(felt252, felt252, felt252), u32>,
    }

    const SESSION_MAGIC: felt252 = 'session-token';

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SessionRevoked: SessionRevoked,
    }

    #[derive(Drop, starknet::Event)]
    struct SessionRevoked {
        session_hash: felt252,
    }

    #[embeddable_as(SessionImpl)]
    impl Sessionable<
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +ISessionCallback<TContractState>,
    > of ISessionable<ComponentState<TContractState>> {
        fn revoke_session(ref self: ComponentState<TContractState>, session_hash: felt252) {
            assert_only_self();
            assert(!self.revoked_session.read(session_hash), 'session/already-revoked');
            self.emit(SessionRevoked { session_hash });
            self.revoked_session.write(session_hash, true);
        }

        #[must_use]
        fn is_session_revoked(self: @ComponentState<TContractState>, session_hash: felt252) -> bool {
            self.revoked_session.read(session_hash)
        }

        #[must_use]
        fn is_session_authorization_cached(
            self: @ComponentState<TContractState>, session_hash: felt252, owner_guid: felt252, guardian_guid: felt252,
        ) -> bool {
            let cached_sig_len = self.valid_session_cache.read((owner_guid, guardian_guid, session_hash));
            if (cached_sig_len == 0) {
                return false;
            }

            let state = self.get_contract();
            state.is_owner_guid(owner_guid) && state.is_guardian_guid(guardian_guid)
        }
    }

    #[generate_trait]
    impl Internal<
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +ISessionCallback<TContractState>,
    > of InternalTrait<TContractState> {
        #[inline(always)]
        fn is_session(self: @ComponentState<TContractState>, signature: Span<felt252>) -> bool {
            match signature.get(0) {
                Option::Some(session_magic) => *session_magic.unbox() == SESSION_MAGIC,
                Option::None => false,
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

            let session_hash = token.session.get_message_hash_rev_1();

            assert(!self.revoked_session.read(session_hash), 'session/revoked');

            assert(token.session.expires_at >= get_block_timestamp(), 'session/expired');

            self
                .assert_valid_session_authorization(
                    state,
                    session_authorization: token.session_authorization,
                    cache_owner_guid: token.cache_owner_guid,
                    token_guardian: token.guardian_signature.signer(),
                    :session_hash,
                );

            let message_hash = PoseidonTrait::new()
                .update_with(transaction_hash)
                .update_with(session_hash)
                .update_with(token.cache_owner_guid)
                .finalize();

            // checks that the session key the user signed is the same key that signed the session
            let session_guid_from_sig = token.session_signature.signer().into_guid();
            assert(token.session.session_key_guid == session_guid_from_sig, 'session/session-key-mismatch');
            let is_valid_session_sig = token.session_signature.is_valid_signature(message_hash);
            assert(is_valid_session_sig || is_estimate_transaction(), 'session/invalid-session-sig');
            // `assert_valid_session_authorization`` will assert the guardian is the same as the one in the
            // authorization
            let is_valid_guardian_sig = token.guardian_signature.is_valid_signature(message_hash);
            assert(is_valid_guardian_sig || is_estimate_transaction(), 'session/invalid-backend-sig');

            assert_valid_session_calls(@token, calls);
        }

        /// @dev guarantees that the authorization is valid (either cached or not)
        /// will store the authorization in the cache when cache_owner_guid is not 0
        /// The guardian from the sessions token must match the guardian from the authorization
        fn assert_valid_session_authorization(
            ref self: ComponentState<TContractState>,
            state: @TContractState,
            session_authorization: Span<felt252>,
            cache_owner_guid: felt252,
            token_guardian: Signer,
            session_hash: felt252,
        ) {
            if cache_owner_guid != 0 {
                // using cache
                let token_guardian_guid = token_guardian.into_guid();
                // Check if the authorization is cached
                let cached_sig_len = self
                    .valid_session_cache
                    .read((cache_owner_guid, token_guardian_guid, session_hash));
                if cached_sig_len != 0 {
                    // assert signers still valid
                    assert(state.is_owner_guid(cache_owner_guid), 'session/cache-invalid-owner');
                    // TODO compare using SignerSignature for performance?
                    assert(state.is_guardian_guid(token_guardian_guid), 'session/cache-invalid-guardian');

                    // prevents a DoS attack where authorization can be replaced by a bigger one
                    assert(session_authorization.len() <= cached_sig_len, 'session/cache-invalid-auth-len');
                    // authorization is cached, we can skip the signature verification
                    return; // authorized
                }
                let parsed_session_authorization = state.validate_authorization(session_hash, session_authorization);
                let owner_guid_from_auth = (*parsed_session_authorization[0]).signer().into_guid();
                // assert guardian in the token is the same guardian as in the authorization
                let guardian_from_auth = (*parsed_session_authorization[1]).signer();
                assert(guardian_from_auth == token_guardian, 'session/guardian-key-mismatch');

                self
                    .valid_session_cache
                    .write((owner_guid_from_auth, token_guardian_guid, session_hash), session_authorization.len());
            } else {
                let parsed_session_authorization = state.validate_authorization(session_hash, session_authorization);

                // assert guardian in the token is the same guardian as in the authorization
                let guardian_from_auth = (*parsed_session_authorization[1]).signer();
                assert(guardian_from_auth == token_guardian, 'session/guardian-key-mismatch');
            }
        }
    }

    fn assert_valid_session_calls(token: @SessionToken, mut calls: Span<Call>) {
        let mut proofs = *token.proofs;
        assert(proofs.len() == calls.len(), 'session/unaligned-proofs');
        let merkle_root = *token.session.allowed_methods_root;
        let mut merkle_tree: MerkleTree<Hasher> = MerkleTreeImpl::new();

        for call in calls {
            let leaf = call.get_merkle_leaf();
            let proof = proofs.pop_front().expect('session/proof-empty');
            let is_valid = merkle_tree.verify(merkle_root, leaf, *proof);
            assert(is_valid, 'session/invalid-call');
        }
    }
}
