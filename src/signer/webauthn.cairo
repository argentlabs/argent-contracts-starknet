use alexandria_encoding::base64::Base64UrlEncoder;
use argent::signer::signer_signature::{WebauthnSigner};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{
    SpanU8TryIntoU256, SpanU8TryIntoFelt252, u32s_to_u256, u32s_typed_to_u256, u32s_to_u8s,
    u256_to_u8s, ArrayU8Ext, u256_to_byte_array, u32s_to_byte_array
};
use argent::utils::hashing::{sha256_cairo0};
use starknet::secp256_trait::Signature;
use core::sha256::compute_sha256_byte_array;

/// @notice The webauthn signature that needs to be validated
/// @param cross_origin From the client data JSON
/// @param top_origin From the client data JSON
/// @param client_data_json_outro The rest of the JSON contents coming after the 'crossOrigin' value
/// @param flags From authenticator data
/// @param sign_count From authenticator data
/// @param ec_signature The signature as {r, s, y_parity}
/// @param sha256_implementation The implementation of the sha256 hash
#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnSignature {
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
    assert!((flags & 0b00000001) == 0b00000001, "webauthn/nonpresent-user");

    // If user verification is required for this signature, verify that the User Verified bit of the
    // flags in authData is set.
    assert!((flags & 0b00000100) == 0b00000100, "webauthn/unverified-user");

    // Allowing attested credential data and extension data if present
    ()
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
/// Encoding spec: https://www.w3.org/TR/webauthn/#clientdatajson-verification
fn encode_client_data_json(
    hash: felt252, signature: WebauthnSignature, origin: Span<u8>
) -> Span<u8> {
    let mut json = client_data_json_intro();
    json.append_all(encode_challenge(hash));
    json.append_all(array!['"', ',', '"', 'o', 'r', 'i', 'g', 'i', 'n', '"', ':', '"'].span());
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
    let result = Base64UrlEncoder::encode(bytes).span();
    // The trailing '=' are ommited as specified in:
    // https://www.w3.org/TR/webauthn-2/#sctn-dependencies
    assert!(result.len() == 44, "webauthn/invalid-challenge-encoding");
    result.slice(0, 43)
}

fn encode_authenticator_data(signature: WebauthnSignature, rp_id_hash: u256) -> ByteArray {
    let mut bytes = u256_to_byte_array(rp_id_hash);
    bytes.append_byte(signature.flags);
    bytes.append(@u32s_to_byte_array(array![signature.sign_count].span()));
    bytes
}

fn get_webauthn_hash(hash: felt252, signer: WebauthnSigner, signature: WebauthnSignature) -> u256 {
    let client_data_json = encode_client_data_json(hash, signature, signer.origin);
    let client_data_hash = compute_sha256_byte_array(@client_data_json.into_byte_array()).span();
    let mut message = encode_authenticator_data(signature, signer.rp_id_hash.into());
    message.append(@u32s_to_byte_array(client_data_hash));
    u32s_typed_to_u256(@compute_sha256_byte_array(@message))
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
