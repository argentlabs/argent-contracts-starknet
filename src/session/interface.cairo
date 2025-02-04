use argent::signer::signer_signature::{Signer, SignerSignature};

/// @notice Session struct that the owner and guardian has to sign to initiate a session
/// @dev The hash of the session is also signed by the guardian (backend) and
/// the dapp (session key) for every session tx (which may include multiple calls)
/// @param expires_at Expiry timestamp of the session (in seconds since the Unix epoch)
/// @param allowed_methods_root The root of the merkle tree of the allowed methods
/// @param metadata_hash The hash of the metadata JSON string of the session
/// @param session_key_guid The GUID of the session key
#[derive(Drop, Serde, Copy)]
pub struct Session {
    pub expires_at: u64,
    pub allowed_methods_root: felt252,
    pub metadata_hash: felt252,
    pub session_key_guid: felt252,
}

/// @notice Session Token struct contains the session struct, relevant signatures and merkle proofs
/// @dev In order to cache the session the owner guid must be passed, otherwise leave as zero
/// @param session The session struct
/// @param cache_owner_guid The guid of the owner that signed the `session_authorization`, or 0 if no caching is desired
/// @param session_authorization A valid account signature over the Session
/// @param session_signature Session signature of the poseidon H(tx_hash, session hash)
/// @param guardian_signature Guardian signature of the poseidon H(tx_hash, session hash)
/// @param proofs The merkle proof of the session calls
#[derive(Drop, Serde, Copy)]
pub struct SessionToken {
    pub session: Session,
    pub cache_owner_guid: felt252,
    // can be the sessions authorization, but also the the CacheInfo struct if the auth was previously cached
    pub session_authorization: Span<felt252>,
    pub session_signature: SignerSignature,
    pub guardian_signature: SignerSignature,
    pub proofs: Span<Span<felt252>>,
}

/// This trait has to be implemented when using the component `session_component` (This is enforced by the compiler)
pub trait ISessionCallback<TContractState> {
    /// @notice Panics if the session authorization is not valid
    /// @param session_hash The hash of session
    /// @param authorization_signature The owner + guardian signature of the session
    /// @return The parsed array of SignerSignature
    fn validate_authorization(
        self: @TContractState, session_hash: felt252, authorization_signature: Span<felt252>,
    ) -> Array<SignerSignature>;

    fn is_owner_guid(self: @TContractState, owner_guid: felt252) -> bool;
    fn is_guardian(self: @TContractState, guardian: Signer) -> bool;
    fn is_guardian_guid(self: @TContractState, guardian_guid: felt252) -> bool;
}

#[starknet::interface]
pub trait ISessionable<TContractState> {
    /// @notice This function allows user to revoke a session based on its hash
    /// @param session_hash Hash of the session token
    fn revoke_session(ref self: TContractState, session_hash: felt252);

    /// @notice View function to see if a session is revoked
    /// @return A boolean indicating whether the session is revoked
    fn is_session_revoked(self: @TContractState, session_hash: felt252) -> bool;

    /// @notice View function to see if a session authorization is cached
    /// @param session_hash Hash of the session token
    /// @param owner_guid Guid of the owner used in the authorization
    /// @return A boolean indicating whether the session is cached
    fn is_session_authorization_cached(
        self: @TContractState, session_hash: felt252, owner_guid: felt252, guardian_guid: felt252,
    ) -> bool;
}
