use alexandria_encoding::base64::Base64UrlEncoder;
use argent::signer::signer_signature::WebauthnSigner;
use argent::utils::array_ext::ArrayExt;
use argent::utils::bytes::{u256_to_u8s, u32s_to_u8s, u32s_to_u256, u8s_to_u32s};
use core::sha256::compute_sha256_u32_array;
use starknet::secp256_trait::Signature;

/// @notice The webauthn signature that needs to be validated
/// @param cross_origin From the client data JSON, some browser don't include this field, so it's optional
/// @param client_data_json_outro The rest of the JSON contents coming after the 'crossOrigin' value
/// @param flags From authenticator data
/// @param sign_count From authenticator data
/// @param ec_signature The signature as {r, s, y_parity}
#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnSignature {
    cross_origin: Option<bool>,
    client_data_json_outro: Span<u8>,
    flags: u8,
    sign_count: u32,
    ec_signature: Signature,
}

/// Example data:
/// 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000000
///   <--------------------------------------------------------------><><------>
///                         rpIdHash (32 bytes)                       ^   sign count (4 bytes)
///                                                    flags (1 byte) |
/// Memory layout: https://www.w3.org/TR/webauthn/#sctn-authenticator-data
fn verify_authenticator_flags(flags: u8) {
    // rpIdHash is verified with the signature over the authenticator

    // Verify that the User Present bit of the flags in authData is set.
    assert!((flags & 0b00000001) == 0b00000001, "webauthn/missing-user-bit");

    // If user verification is required for this signature, verify that the User Verified bit of the flags in authData
    // is set.
    assert!((flags & 0b00000100) == 0b00000100, "webauthn/unverified-user");
    // Allowing attested credential data and extension data if present
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
/// Encoding spec: https://www.w3.org/TR/webauthn/#clientdatajson-verification
//  Try origin as ByteArray ==> Cost is marginal to pass origin as ByteArray
fn encode_client_data_json(hash: felt252, signature: WebauthnSignature, origin: Span<u8>) -> Array<u8> {
    let mut json = client_data_json_intro();
    json.append_all(encode_challenge(hash));
    json.append_all(['"', ',', '"', 'o', 'r', 'i', 'g', 'i', 'n', '"', ':', '"'].span());
    json.append_all(origin);
    json.append('"');
    if let Option::Some(cross_origin) = signature.cross_origin {
        json.append_all([',', '"', 'c', 'r', 'o', 's', 's', 'O', 'r', 'i', 'g', 'i', 'n', '"', ':'].span());
        if cross_origin {
            json.append_all(['t', 'r', 'u', 'e'].span());
        } else {
            json.append_all(['f', 'a', 'l', 's', 'e'].span());
        }
    };
    if signature.client_data_json_outro.is_empty() {
        json.append('}');
    } else {
        assert!(*signature.client_data_json_outro.at(0) == ',', "webauthn/invalid-json-outro");
        json.append_all(signature.client_data_json_outro);
    }
    json
}

fn encode_challenge(hash: felt252) -> Span<u8> {
    let mut bytes = u256_to_u8s(hash.into());
    bytes.append(0);
    assert!(bytes.len() == 33, "webauthn/invalid-challenge-length"); // remove '=' signs if this assert fails
    Base64UrlEncoder::encode(bytes).span()
}

fn encode_authenticator_data(signature: WebauthnSignature, rp_id_hash: u256) -> Array<u8> {
    let mut bytes = u256_to_u8s(rp_id_hash);
    bytes.append(signature.flags);
    bytes.append(0);
    bytes.append(0);
    bytes.append(0);
    bytes.append(signature.sign_count.try_into().unwrap());
    bytes
}

fn get_webauthn_hash(hash: felt252, signer: WebauthnSigner, signature: WebauthnSignature) -> u256 {
    let client_data_json = encode_client_data_json(hash, signature, signer.origin);
    let (word_arr, last, rem) = u8s_to_u32s(client_data_json.span());
    let mut client_data = u32s_to_u8s(compute_sha256_u32_array(word_arr, last, rem).span());

    let mut arr = encode_authenticator_data(signature, signer.rp_id_hash.into());
    while let Option::Some(byte) = client_data.pop_front() {
        arr.append(*byte);
    };

    let (word_arr, last, rem) = u8s_to_u32s(arr.span());

    u32s_to_u256(compute_sha256_u32_array(word_arr, last, rem).span())
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
