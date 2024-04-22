use alexandria_encoding::base64::Base64UrlEncoder;
use alexandria_math::sha256::{sha256};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{SpanU8TryIntoU256, SpanU8TryIntoFelt252, u32s_to_u256, u32s_to_u8s};
use argent::utils::hashing::{sha256_cairo0};
use starknet::secp256_trait::Signature;

/// @notice The webauthn asserion that needs to be validated
/// @param authenticator_data The data returned by the authenticator
/// @param transaction_hash The transaction hash encoded in the challenge
/// @param sha256_implementation The implementation of the sha256 hash 
/// @param client_data_json_outro The rest of the JSON contents coming after the 'origin' value
/// @param signature The signature as {r, s, y_parity}
#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnAssertion {
    authenticator_data: Span<u8>,
    transaction_hash: Span<u8>,
    sha256_implementation: Sha256Implementation,
    client_data_json_outro: Span<u8>,
    signature: Signature,
}

#[derive(Drop, Copy, Serde, PartialEq)]
enum Sha256Implementation {
    Cairo0,
    Cairo1,
}

fn verify_transaction_hash(assertion: WebauthnAssertion, expected_transaction_hash: felt252) {
    let transaction_hash = assertion.transaction_hash.try_into().expect('invalid-transaction-hash-format');
    assert(transaction_hash == expected_transaction_hash, 'invalid-transaction-hash');
}

/// Example data:
/// 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000000
///   <--------------------------------------------------------------><><------>
///                         rpIdHash (32 bytes)                       ^   sign count (4 bytes)
///                                                    flags (1 byte) | 
/// Memory layout: https://www.w3.org/TR/webauthn/#sctn-authenticator-data
fn verify_authenticator_data(authenticator_data: Span<u8>, expected_rp_id_hash: u256) {
    // Verify that the rpIdHash in authData is the SHA-256 hash of the RP ID expected by the Relying Party. 
    let actual_rp_id_hash = authenticator_data.slice(0, 32).try_into().expect('invalid-rp-id-hash');
    assert(actual_rp_id_hash == expected_rp_id_hash, 'invalid-rp-id');

    // Verify that the User Present bit of the flags in authData is set.
    let flags: u128 = (*authenticator_data.at(32)).into();
    assert((flags & 0b00000001) == 0b00000001, 'nonpresent-user');

    // If user verification is required for this assertion, verify that the User Verified bit of the flags in authData is set.
    assert((flags & 0b00000100) == 0b00000100, 'unverified-user');
    // Allowing attested credential data and extension data if present
    ()
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
fn build_client_data_json(assertion: WebauthnAssertion, origin: Span<u8>) -> Span<u8> {
    let mut json = client_data_json_intro();
    json.append_all(encode_challenge(assertion));
    json.append_all(array!['"', ',', '"', 'o', 'r', 'i', 'g', 'i', 'n', '"', ':', '"'].span());
    json.append_all(origin);
    json.append_all(assertion.client_data_json_outro);
    json.span()
}

fn encode_challenge(assertion: WebauthnAssertion) -> Span<u8> {
    let mut bytes = assertion.transaction_hash.snapshot.clone();
    let last_byte = match assertion.sha256_implementation {
        Sha256Implementation::Cairo0 => 0,
        Sha256Implementation::Cairo1 => 1,
    };
    bytes.append(last_byte);
    Base64UrlEncoder::encode(bytes).span()
}

fn get_webauthn_hash_cairo0(assertion: WebauthnAssertion, origin: Span<u8>) -> Option<u256> {
    let client_data_json = build_client_data_json(assertion, origin);
    let client_data_hash = u32s_to_u8s(sha256_cairo0(client_data_json)?);
    let mut message = assertion.authenticator_data.snapshot.clone();
    message.append_all(client_data_hash);
    Option::Some(u32s_to_u256(sha256_cairo0(message.span())?))
}

fn get_webauthn_hash_cairo1(assertion: WebauthnAssertion, origin: Span<u8>) -> u256 {
    let client_data_json = build_client_data_json(assertion, origin);
    let client_data_hash = sha256(client_data_json.snapshot.clone()).span();
    let mut message = assertion.authenticator_data.snapshot.clone();
    message.append_all(client_data_hash);
    sha256(message).span().try_into().expect('invalid-hash')
}

fn get_webauthn_hash(assertion: WebauthnAssertion, origin: Span<u8>) -> u256 {
    match assertion.sha256_implementation {
        Sha256Implementation::Cairo0 => get_webauthn_hash_cairo0(assertion, origin).expect('sha256-cairo0-failed'),
        Sha256Implementation::Cairo1 => get_webauthn_hash_cairo1(assertion, origin),
    }
}

fn client_data_json_intro() -> Array<u8> {
    array![
        '{',
        '"',
        't',
        'y',
        'p',
        'e',
        '"',
        ':',
        '"',
        'w',
        'e',
        'b',
        'a',
        'u',
        't',
        'h',
        'n',
        '.',
        'g',
        'e',
        't',
        '"',
        ',',
        '"',
        'c',
        'h',
        'a',
        'l',
        'l',
        'e',
        'n',
        'g',
        'e',
        '"',
        ':',
        '"'
    ]
}
