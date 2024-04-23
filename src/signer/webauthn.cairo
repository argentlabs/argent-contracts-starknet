use alexandria_encoding::base64::Base64UrlEncoder;
use alexandria_math::sha256::{sha256};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{SpanU8TryIntoU256, SpanU8TryIntoFelt252, u32s_to_u256, u32s_to_u8s, u256_to_u8s};
use argent::utils::hashing::{sha256_cairo0};
use starknet::secp256_trait::Signature;

/// @notice The webauthn asserion that needs to be validated
/// @param authenticator_data The data returned by the authenticator
/// @param transaction_hash The transaction hash encoded in the challenge
/// @param sha256_implementation The implementation of the sha256 hash 
/// @param client_data_json_outro The rest of the JSON contents coming after the 'crossOrigin' value
/// @param signature The signature as {r, s, y_parity}
#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnAssertion {
    authenticator_data: AuthenticatorData,
    cross_origin: bool,
    client_data_json_outro: Span<u8>,
    sha256_implementation: Sha256Implementation,
    signature: Signature,
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct AuthenticatorData {
    rp_id_hash: u256,
    flags: u8,
    sign_count: u32,
}

#[derive(Drop, Copy, Serde, PartialEq)]
enum Sha256Implementation {
    Cairo0,
    Cairo1,
}

/// Example data:
/// 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000000
///   <--------------------------------------------------------------><><------>
///                         rpIdHash (32 bytes)                       ^   sign count (4 bytes)
///                                                    flags (1 byte) | 
/// Memory layout: https://www.w3.org/TR/webauthn/#sctn-authenticator-data
fn verify_authenticator_data(authenticator_data: AuthenticatorData, expected_rp_id_hash: u256) {
    // Verify that the rpIdHash in authData is the SHA-256 hash of the RP ID expected by the Relying Party. 
    assert(authenticator_data.rp_id_hash == expected_rp_id_hash, 'invalid-rp-id');

    // Verify that the User Present bit of the flags in authData is set.
    assert((authenticator_data.flags & 0b00000001) == 0b00000001, 'nonpresent-user');

    // If user verification is required for this assertion, verify that the User Verified bit of the flags in authData is set.
    assert((authenticator_data.flags & 0b00000100) == 0b00000100, 'unverified-user');

    // Allowing attested credential data and extension data if present
    ()
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
/// Encoding spec: https://www.w3.org/TR/webauthn/#clientdatajson-verification
fn encode_client_data_json(assertion: WebauthnAssertion, origin: Span<u8>, hash: felt252) -> Span<u8> {
    let mut json = client_data_json_intro();
    json.append_all(encode_challenge(hash, assertion.sha256_implementation));
    json.append_all(array!['"', ',', '"', 'o', 'r', 'i', 'g', 'i', 'n', '"', ':', '"'].span());
    json.append_all(origin);
    json.append_all(array!['"', ',', '"', 'c', 'r', 'o', 's', 's', 'O', 'r', 'i', 'g', 'i', 'n', '"', ':'].span());
    if assertion.cross_origin {
        json.append_all(array!['t', 'r', 'u', 'e'].span());
    } else {
        json.append_all(array!['f', 'a', 'l', 's', 'e'].span());
    }
    if assertion.client_data_json_outro.is_empty() {
        json.append('}');
    } else {
        json.append(',');
        json.append_all(assertion.client_data_json_outro);
    }
    json.span()
}

fn encode_challenge(hash: felt252, sha256_implementation: Sha256Implementation) -> Span<u8> {
    let mut bytes = u256_to_u8s(hash.into());
    let last_byte = match sha256_implementation {
        Sha256Implementation::Cairo0 => 0,
        Sha256Implementation::Cairo1 => 1,
    };
    bytes.append(last_byte);
    assert(bytes.len() == 33, 'invalid-challenge-length'); // remove appended '=' signs if this assertion fails
    let encoded = Base64UrlEncoder::encode(bytes).span();
    encoded
}

fn encode_authenticator_data(authenticator_data: AuthenticatorData) -> Array<u8> {
    let mut bytes = u256_to_u8s(authenticator_data.rp_id_hash);
    bytes.append(authenticator_data.flags);
    bytes.append_all(u32s_to_u8s(array![authenticator_data.sign_count.into()].span()));
    bytes
}

fn get_webauthn_hash_cairo0(authenticator_data: AuthenticatorData, client_data_json: Span<u8>) -> Option<u256> {
    let client_data_hash = u32s_to_u8s(sha256_cairo0(client_data_json)?);
    let mut message = encode_authenticator_data(authenticator_data);
    message.append_all(client_data_hash);
    Option::Some(u32s_to_u256(sha256_cairo0(message.span())?))
}

fn get_webauthn_hash_cairo1(authenticator_data: AuthenticatorData, client_data_json: Span<u8>) -> u256 {
    let client_data_hash = sha256(client_data_json.snapshot.clone()).span();
    let mut message = encode_authenticator_data(authenticator_data);
    message.append_all(client_data_hash);
    sha256(message).span().try_into().expect('invalid-hash')
}

fn get_webauthn_hash(assertion: WebauthnAssertion, origin: Span<u8>, hash: felt252) -> u256 {
    let client_data_json = encode_client_data_json(assertion, origin, hash);
    match assertion.sha256_implementation {
        Sha256Implementation::Cairo0 => get_webauthn_hash_cairo0(assertion.authenticator_data, client_data_json)
            .expect('sha256-cairo0-failed'),
        Sha256Implementation::Cairo1 => get_webauthn_hash_cairo1(assertion.authenticator_data, client_data_json),
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
