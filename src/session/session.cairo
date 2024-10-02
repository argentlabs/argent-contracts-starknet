#[starknet::component]
mod session_component {
    use alexandria_merkle_tree::merkle_tree::{
        Hasher, MerkleTree, MerkleTreeImpl, poseidon::PoseidonHasherImpl, MerkleTreeTrait,
    };
    use argent::account::interface::{IAccount};
    use argent::session::{
        session_hash::{OffChainMessageHashSessionRev1, MerkleLeafHash},
        interface::{ISessionable, SessionToken, Session, ISessionCallback},
    };
    use argent::signer::signer_signature::{SignerSignatureTrait, SignerTrait, SignerSignature};
    use argent::utils::{asserts::{assert_no_self_call, assert_only_self}, serialization::full_deserialize};
    use hash::{HashStateExTrait, HashStateTrait};
    use poseidon::PoseidonTrait;
    use starknet::{account::Call, get_contract_address, VALIDATED, get_block_timestamp, storage::Map};


    #[storage]
    struct Storage {
        /// A map of session hashes to a boolean indicating if the session has been revoked.
        revoked_session: Map<felt252, bool>,
        // TODO remove if no backwards compatibility is needed
        // /// A map of (owner_guid, guardian_guid, session_hash) to a len of authorization signature
        // valid_session_cache: Map<(felt252, felt252, felt252), u32>,
        /// A map of (guardian_guid, session_hash) to a (owner_guid, len of authorization signature)
        valid_session_cache_v2: Map<(felt252, felt252), (felt252, u32)>,
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
        TContractState, +HasComponent<TContractState>, +IAccount<TContractState>, +ISessionCallback<TContractState>,
    > of ISessionable<ComponentState<TContractState>> {
        fn revoke_session(ref self: ComponentState<TContractState>, session_hash: felt252) {
            assert_only_self();
            assert(!self.revoked_session.read(session_hash), 'session/already-revoked');
            self.emit(SessionRevoked { session_hash });
            self.revoked_session.write(session_hash, true);
        }

        #[inline(always)]
        #[must_use]
        fn is_session_revoked(self: @ComponentState<TContractState>, session_hash: felt252) -> bool {
            self.revoked_session.read(session_hash)
        }

        #[inline(always)]
        #[must_use]
        fn is_session_authorization_cached(
            self: @ComponentState<TContractState>, session_hash: felt252, session_authorization: Span<felt252>
        ) -> bool {
            let state = self.get_contract();

            let guardian_guid = if let Option::Some(guardian_guid) = state.get_guardian_guid_callback() {
                guardian_guid
            } else {
                // No guardian, can't be cached
                return false;
            };

            let parsed_session_authorization = state.parse_authorization(session_authorization);
            // owner + guardian signed
            assert(parsed_session_authorization.len() == 2, 'session/invalid-signature-len');
            let signature_owner_guid = (*parsed_session_authorization[0]).signer().into_guid();

            // self.valid_session_cache.read((signature_owner_guid, guardian_guid, session_hash)).is_non_zero()
            let (cached_owner_guid, cached_sig_len) = self.valid_session_cache_v2.read((guardian_guid, session_hash));
            if (cached_sig_len == 0) {
                return false;
            }
            assert(cached_owner_guid == signature_owner_guid, 'session/cached-owner-mismatch');
            state.is_owner_guid(signature_owner_guid)
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

            self
                .assert_valid_session_authorization(
                    state, token.session_authorization, token.cache_authorization, token_session_hash
                );

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
            let current_guardian_guid = state.get_guardian_guid_callback().expect('session/no-guardian');
            assert(
                current_guardian_guid == token.guardian_signature.signer().into_guid(), 'session/guardian-key-mismatch'
            );
            assert(token.guardian_signature.is_valid_signature(message_hash), 'session/invalid-backend-sig');

            assert_valid_session_calls(@token, calls);
        }


        fn assert_valid_session_authorization(
            ref self: ComponentState<TContractState>,
            state: @TContractState,
            session_authorization: Span<felt252>,
            use_cache: bool,
            session_hash: felt252,
        ) {
            let current_guardian_guid = state.get_guardian_guid_callback().expect('session/no-guardian');

            if use_cache {
                // Check if cached
                let (cached_owner_guid, cached_sig_len) = self
                    .valid_session_cache_v2
                    .read((current_guardian_guid, session_hash));
                // check in the old cache too? TODO
                if cached_sig_len != 0 {
                    // assert owner is still valid
                    assert(state.is_owner_guid(cached_owner_guid), 'session/signer-is-not-owner');
                    // prevents a DoS attack where authorization can be replaced by a bigger one
                    assert(session_authorization.len() <= cached_sig_len, 'session/invalid-auth-len');
                    // authorization is cached, we can skip the signature verification
                    return;
                }
            }
            // not cached, continue to verification

            let parsed_session_authorization = state.parse_authorization(session_authorization);
            state.assert_valid_authorization(session_hash, parsed_session_authorization.span());
            // owner + guardian signed
            assert(parsed_session_authorization.len() == 2, 'session/invalid-signature-len');
            let owner_guid_from_sig = (*parsed_session_authorization[0]).signer().into_guid();
            let guardian_guid_from_sig = (*parsed_session_authorization[1]).signer().into_guid();
            // checks that second signature is the guardian and not the backup guardian
            assert(guardian_guid_from_sig == current_guardian_guid, 'session/signer-is-not-guardian');

            if use_cache {
                self
                    .valid_session_cache_v2
                    .write((current_guardian_guid, session_hash), (owner_guid_from_sig, session_authorization.len()));
            }
        }
    }

    fn assert_valid_session_calls(token: @SessionToken, mut calls: Span<Call>) {
        assert((*token.proofs).len() == calls.len(), 'session/unaligned-proofs');
        let merkle_root = *token.session.allowed_methods_root;
        let mut merkle_tree: MerkleTree<Hasher> = MerkleTreeImpl::new();
        let mut proofs = *token.proofs;
        while let Option::Some(call) = calls.pop_front() {
            let leaf = call.get_merkle_leaf();
            let proof = proofs.pop_front().expect('session/proof-empty');
            let is_valid = merkle_tree.verify(merkle_root, leaf, *proof);
            assert(is_valid, 'session/invalid-call');
        };
    }
}
