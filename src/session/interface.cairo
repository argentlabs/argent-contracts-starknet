use argent::signer::signer_signature::SignerSignature;
use poseidon::poseidon_hash_span;
use starknet::account::Call;
use starknet::{get_tx_info, get_contract_address, ContractAddress};

/// @notice Session struct that the owner and guardian has to sign to initiate a session
/// @dev The hash of the session is also signed by the guardian (backend) and 
/// the dapp (session key) for every session tx (which may include multiple calls)
/// @param expires_at Expiry timestamp of the session (seconds)
/// @param allowed_methods_root The root of the merkle tree of the allowed methods
/// @param metadata_hash The hash of the metadata JSON string of the session
/// @param session_key_guid The GUID of the session key
/// @param guardian_key_guid The GUID of the session key
#[derive(Drop, Serde, Copy)]
struct Session {
    expires_at: u64,
    allowed_policies_root: felt252,
    metadata_hash: felt252,
    session_key_guid: felt252,
    guardian_key_guid: felt252,
}



/// @notice Session Token struct contains the session struct, relevant signatures and merkle proofs
/// @param session The session struct
/// @param cache_authorization Flag indicating whether to cache the authorization signature for the session
/// @param session_authorization A valid account signature over the Session
/// @param session_signature Session signature of the poseidon H(tx_hash, session hash)
/// @param guardian_signature Guardian signature of the poseidon H(tx_hash, session hash)
/// @param proofs The merkle proof of the session calls
#[derive(Drop, Serde, Copy)]
struct SessionToken {
    session: Session,
    cache_authorization: bool,
    session_authorization: Span<felt252>,
    session_signature: SignerSignature,
    guardian_signature: SignerSignature,
    proofs: Span<Span<felt252>>,
}

/// @param scope_hash Commitment computed as `poseidon(domain_separator_hash, type_hash)`
/// @param typed_data_hash Encoded data for the primary type as a single `felt252`
#[derive(Drop, Serde, Copy)]
struct TypedData {
    scope_hash: felt252,
    typed_data_hash: felt252,
}

#[derive(Drop, Serde, Copy)]
struct DetailedTypedData {
    domain_hash: felt252,
    type_hash: felt252,
    params: Span<felt252>,
}

#[derive(Drop, Serde, Copy)]
enum Policy {
    Call: Call,
    TypedData: TypedData,
}


/// This trait has to be implemented when using the component `session_component` (This is enforced by the compiler)
#[starknet::interface]
trait ISessionCallback<TContractState> {
    /// @notice Callback performed to parse and validate account signature
    /// @param session_hash The hash of session
    /// @param authorization_signature The owner + guardian signature of the session
    /// @return The parsed array of SignerSignature
    fn parse_and_verify_authorization(
        self: @TContractState, session_hash: felt252, authorization_signature: Span<felt252>
    ) -> Array<SignerSignature>;
}

#[starknet::interface]
trait ISessionable<TContractState> {
    /// @notice This function allows user to revoke a session based on its hash
    /// @param session_hash Hash of the session token
    fn revoke_session(ref self: TContractState, session_hash: felt252);

    /// @notice View function to see if a session is revoked, returns a boolean 
    fn is_session_revoked(self: @TContractState, session_hash: felt252) -> bool;

    /// @notice View function to see if a session authorization is cached
    /// @param session_hash Hash of the session token
    /// @return Whether the session is cached
    fn is_session_authorization_cached(self: @TContractState, session_hash: felt252) -> bool;
}
