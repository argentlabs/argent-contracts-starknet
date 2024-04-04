use alexandria_encoding::base64::Base64UrlDecoder;
use alexandria_math::sha256::{sha256};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{SpanU8TryIntoU256, SpanU8TryIntoFelt252, u32s_to_u256, u32s_to_u8s};
use argent::utils::hashing::{sha256_cairo0};
use starknet::secp256_trait::Signature;

#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnAssertion {
    authenticator_data: Span<u8>,
    client_data_json: Span<u8>,
    signature: Signature,
    type_offset: usize,
    challenge_offset: usize,
    challenge_length: usize,
    origin_offset: usize,
    origin_length: usize,
}

#[derive(Drop, Copy, PartialEq, Serde, Default)]
struct Challenge {
    transaction_hash: felt252,
    sha256_implementation: Sha256Implementation,
}

#[derive(Drop, Copy, PartialEq, Serde, Default)]
enum Sha256Implementation {
    #[default]
    Native,
    Cairo0,
    Cairo1,
}

fn deserialize_challenge(challenge: Span<u8>) -> Challenge {
    assert(challenge.len() == 32 || challenge.len() == 34, 'invalid-challenge-length');
    let transaction_hash = challenge.slice(0, 32).try_into().unwrap();
    if challenge.len() == 32 {
        Challenge { transaction_hash, ..Default::default() }
    } else {
        assert(*challenge.at(32) == 0xEF, 'invalid-challenge-magic');
        let sha256_implementation = match *challenge.at(33) {
            0 => Sha256Implementation::Native,
            1 => Sha256Implementation::Cairo1,
            2 => Sha256Implementation::Cairo0,
            _ => panic_with_felt252('invalid-challenge-sha256'),
        };
        Challenge { transaction_hash, sha256_implementation }
    }
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
fn verify_client_data_json(
    assertion: WebauthnAssertion, expected_transaction_hash: felt252, expected_origin: felt252
) -> Challenge {
    // 11. Verify that the value of C.type is the string webauthn.get.
    let WebauthnAssertion { client_data_json, type_offset, .. } = assertion;
    let key = array!['"', 't', 'y', 'p', 'e', '"', ':', '"'];
    let actual_key = client_data_json.slice(type_offset - key.len(), key.len());
    assert(actual_key == key.span(), 'invalid-type-key');

    let expected = array!['"', 'w', 'e', 'b', 'a', 'u', 't', 'h', 'n', '.', 'g', 'e', 't', '"'];
    let type_ = client_data_json.slice(type_offset - 1, expected.len());
    assert(type_ == expected.span(), 'invalid-type');

    // 12. Verify that the value of C.challenge equals the base64url encoding of options.challenge.
    let WebauthnAssertion { challenge_offset, challenge_length, .. } = assertion;
    let key = array!['"', 'c', 'h', 'a', 'l', 'l', 'e', 'n', 'g', 'e', '"', ':', '"'];
    let actual_key = client_data_json.slice(challenge_offset - key.len(), key.len());
    assert(actual_key == key.span(), 'invalid-challenge-key');

    let challenge = client_data_json.slice(challenge_offset, challenge_length);
    let challenge = decode_base64(challenge.snapshot.clone()).span();
    let challenge = deserialize_challenge(challenge);
    assert(challenge.transaction_hash == expected_transaction_hash, 'invalid-transaction-hash');

    // 13. Verify that the value of C.origin matches the Relying Party's origin.
    let WebauthnAssertion { origin_offset, origin_length, .. } = assertion;
    let key = array!['"', 'o', 'r', 'i', 'g', 'i', 'n', '"', ':', '"'];
    let actual_key = client_data_json.slice(origin_offset - key.len(), key.len());
    assert(actual_key == key.span(), 'invalid-origin-key');

    let origin = client_data_json.slice(origin_offset, origin_length).try_into().expect('invalid-origin');
    assert(origin == expected_origin, 'invalid-origin');

    // 14. Skipping tokenBindings

    challenge
}

/// Example data:
/// 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000000
///   <--------------------------------------------------------------><><------>
///                         rpIdHash (32 bytes)                       ^   sign count (4 bytes)
///                                                    flags (1 byte) | 
/// Memory layout: https://www.w3.org/TR/webauthn/#sctn-authenticator-data
fn verify_authenticator_data(authenticator_data: Span<u8>, expected_rp_id_hash: u256) {
    // 15. Verify that the rpIdHash in authData is the SHA-256 hash of the RP ID expected by the Relying Party. 
    let actual_rp_id_hash = authenticator_data.slice(0, 32).try_into().expect('invalid-rp-id-hash');
    assert(actual_rp_id_hash == expected_rp_id_hash, 'invalid-rp-id');

    // 16. Verify that the User Present bit of the flags in authData is set.
    let flags: u128 = (*authenticator_data.at(32)).into();
    assert((flags & 0b00000001) == 0b00000001, 'nonpresent-user');

    // 17. If user verification is required for this assertion, verify that the User Verified bit of the flags in authData is set.
    assert((flags & 0b00000100) == 0b00000100, 'unverified-user');

    // 18. Allowing attested credential data and extension data if present
    ()
}

fn decode_base64(mut encoded: Array<u8>) -> Array<u8> {
    // TODO: should this be added to alexandria? https://gist.github.com/catwell/3046205
    let len_mod_4 = encoded.len() % 4;
    if len_mod_4 == 2 {
        encoded.append('=');
        encoded.append('=');
    } else if len_mod_4 == 3 {
        encoded.append('=');
    }
    let decoded = Base64UrlDecoder::decode(encoded);
    decoded
}

fn get_webauthn_hash_cairo0(assertion: WebauthnAssertion) -> Option<u256> {
    let WebauthnAssertion { authenticator_data, client_data_json, .. } = assertion;
    let client_data_hash = u32s_to_u8s(sha256_cairo0(client_data_json)?);
    let mut message = authenticator_data.snapshot.clone();
    message.append_all(client_data_hash);
    Option::Some(u32s_to_u256(sha256_cairo0(message.span())?))
}

fn get_webauthn_hash_cairo1(assertion: WebauthnAssertion) -> u256 {
    let WebauthnAssertion { authenticator_data, client_data_json, .. } = assertion;
    let client_data_hash = sha256(client_data_json.snapshot.clone()).span();
    let mut message = authenticator_data.snapshot.clone();
    message.append_all(client_data_hash);
    sha256(message).span().try_into().expect('invalid-hash')
}

fn get_webauthn_hash(assertion: WebauthnAssertion, challenge: Challenge) -> u256 {
    match challenge.sha256_implementation {
        Sha256Implementation::Native => panic_with_felt252('unimplemented native sha256'),
        Sha256Implementation::Cairo0 => get_webauthn_hash_cairo0(assertion).expect('sha256-cairo0-failed'),
        Sha256Implementation::Cairo1 => get_webauthn_hash_cairo1(assertion),
    }
}
