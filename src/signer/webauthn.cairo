use alexandria_encoding::base64::Base64UrlEncoder;
use argent::signer::signer_signature::WebauthnSigner;
use argent::utils::array_ext::ArrayExt;
use argent::utils::bytes::{bytes_to_u32s, eight_words_to_bytes, eight_words_to_u256, u256_to_u8s, u32_to_bytes};
use core::sha256::compute_sha256_u32_array;
use starknet::secp256_trait::Signature;

/// @notice The webauthn signature that needs to be validated
/// @param client_data_json_outro The rest of the JSON contents coming after the 'origin' value
/// @param flags From authenticator data
/// @param sign_count From authenticator data
/// @param ec_signature The signature as {r, s, y_parity}
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct WebauthnSignature {
    pub client_data_json_outro: Span<u8>,
    pub flags: u8,
    pub sign_count: u32,
    pub ec_signature: Signature,
}

/// Example data:
/// 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000000
///   <--------------------------------------------------------------><><------>
///                         rpIdHash (32 bytes)                       ^   sign count (4 bytes)
///                                                    flags (1 byte) |
/// Memory layout: https://www.w3.org/TR/webauthn/#sctn-authenticator-data
pub fn verify_authenticator_flags(flags: u8) {
    // rpIdHash is verified with the signature over the authenticator

    // Verify that the User Present bit of the flags in authData is set.
    assert!((flags & 0b00000001) == 0b00000001, "webauthn/nonpresent-user");

    // If user verification is required for this signature, verify that the User Verified bit of the flags in authData
    // is set.
    assert!((flags & 0b00000100) == 0b00000100, "webauthn/unverified-user");
    // Allowing attested credential data and extension data if present
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
/// Encoding spec: https://www.w3.org/TR/webauthn/#clientdatajson-verification
fn encode_client_data_json(hash: felt252, signature: WebauthnSignature, origin: Span<u8>) -> Span<u8> {
    let mut json = client_data_json_intro();
    json.append_all(encode_challenge(hash));
    json.append_all(['"', ',', '"', 'o', 'r', 'i', 'g', 'i', 'n', '"', ':', '"'].span());
    json.append_all(origin);
    json.append('"');
    if !signature.client_data_json_outro.is_empty() {
        assert!(*signature.client_data_json_outro.at(0) == ',', "webauthn/invalid-json-outro");
        json.append_all(signature.client_data_json_outro);
    } else {
        json.append('}');
    }
    json.span()
}

fn encode_challenge(hash: felt252) -> Span<u8> {
    let mut bytes = u256_to_u8s(hash.into());

    assert!(bytes.len() == 32, "webauthn/invalid-challenge-length");
    // Base64 encodes takes every 3bytes and encodes them as 4bytes.
    // Since we are encoding 32bytes. ((32 / 3) * 4) = 42.666.. bytes.
    // The trailing '=' are omitted as specified in the spec:
    // https://www.w3.org/TR/webauthn-2/#sctn-dependencies
    // So this gets padded to the next byte only
    let mut encoded_bytes = Base64UrlEncoder::encode(bytes).span();
    assert!(encoded_bytes.len() == 44, "webauthn/invalid-challenge-encoding");
    let last_char = *encoded_bytes.pop_back().unwrap();
    assert!(last_char == '=', "webauthn/invalid-challenge-encoding");
    encoded_bytes
}

fn encode_authenticator_data(signature: WebauthnSignature, rp_id_hash: u256) -> Array<u8> {
    let mut bytes = u256_to_u8s(rp_id_hash);
    bytes.append(signature.flags);
    // According to the spec, the sign count should be 4 bytes long.
    // But is very often zero when using passkeys.
    if signature.sign_count == 0 {
        bytes.append(0);
        bytes.append(0);
        bytes.append(0);
        bytes.append(0);
    } else {
        let [byte_1, byte_2, byte_3, byte_4] = u32_to_bytes(signature.sign_count);
        bytes.append(byte_1);
        bytes.append(byte_2);
        bytes.append(byte_3);
        bytes.append(byte_4);
    }
    bytes
}

pub fn get_webauthn_hash(hash: felt252, signer: WebauthnSigner, signature: WebauthnSignature) -> u256 {
    let mut message = encode_authenticator_data(signature, signer.rp_id_hash.into());

    let client_data_json = encode_client_data_json(hash, signature, signer.origin);
    let client_data_hash = eight_words_to_bytes(sha256_u8s(client_data_json));
    message.append_all(client_data_hash.span());

    eight_words_to_u256(sha256_u8s(message.span()))
}

fn sha256_u8s(arr: Span<u8>) -> [u32; 8] {
    let (word_arr, last, rem) = bytes_to_u32s(arr);
    compute_sha256_u32_array(word_arr, last, rem)
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
        '"',
    ]
}
