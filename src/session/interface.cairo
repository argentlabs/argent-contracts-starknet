use argent::signer::signer_signature::{SignerSignature};
use poseidon::{poseidon_hash_span};
use starknet::account::Call;
use starknet::{get_tx_info, get_contract_address, ContractAddress};


/// This trait has to be implemented when using the component `session_component` (This is enforced by the compiler)
#[starknet::interface]
trait ISessionCallback<TContractState> {
    /// @notice Callback performed to check valid account signature
    /// @param session_hash The hash of session
    /// @param authorization_signature The owner + guardian signature of the session
    fn session_callback(self: @TContractState, session_hash: felt252, authorization_signature: Span<felt252>) -> bool;
}

#[starknet::interface]
trait ISessionable<TContractState> {
    /// @notice This method allows user to revoke a session based on its hash
    /// @param session_hash Hash of the session token
    fn revoke_session(ref self: TContractState, session_hash: felt252);

    /// @notice View method to see if a session is revoked, returns a boolean 
    fn is_session_revoked(self: @TContractState, session_hash: felt252) -> bool;
}

#[derive(Drop, Serde, Copy)]
struct Session {
    expires_at: u64,
    allowed_methods_root: felt252,
    metadata_hash: felt252,
    session_key_guid: felt252,
}

#[derive(Drop, Serde, Copy)]
struct SessionToken {
    session: Session,
    session_authorisation: Span<felt252>,
    session_signature: SignerSignature,
    guardian_signature: SignerSignature,
    proofs: Span<Span<felt252>>,
}
