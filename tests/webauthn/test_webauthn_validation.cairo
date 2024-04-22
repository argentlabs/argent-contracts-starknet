use argent::signer::signer_signature::{Secp256r1Signer, is_valid_webauthn_signature, is_valid_secp256r1_signature};
use argent::signer::webauthn::{WebauthnAssertion, get_webauthn_hash, verify_challenge, verify_authenticator_data};
use starknet::SyscallResultTrait;
use starknet::{EthAddress, eth_signature::{Signature as Secp256k1Signature, is_eth_signature_valid}};
use super::super::setup::webauthn_test_setup::{setup_1};

#[test]
fn test_is_valid_webauthn_signature() {
    let (transaction_hash, signer, assertion) = setup_1();
    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, assertion);
    assert!(is_valid, "invalid");
}

#[test]
fn test_is_valid_webauthn_validation() {
    let (transaction_hash, signer, assertion) = setup_1();

    let sha256_implementation = verify_challenge(assertion.challenge, transaction_hash);
    verify_authenticator_data(assertion.authenticator_data, signer.rp_id_hash.into());

    let signed_hash = get_webauthn_hash(assertion, signer.origin, sha256_implementation);
    let signer = Secp256r1Signer { pubkey: signer.pubkey };
    let is_valid = is_valid_secp256r1_signature(signed_hash, signer, assertion.signature);

    assert!(is_valid, "invalid");
}
