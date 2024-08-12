use argent::signer::signer_signature::WebauthnSigner;
use argent::utils::bytes::{u256_to_u8s, u8s_to_u32s_pad_end};
use core::byte_array::ByteArrayTrait;
use core::sha256::{compute_sha256_byte_array, compute_sha256_u32_array};
use starknet::secp256_trait::Signature;

/// @notice The webauthn signature that needs to be validated
/// @param cross_origin From the client data JSON
/// @param client_data_json_outro The rest of the JSON contents coming after the 'crossOrigin' value
/// @param flags From authenticator data
/// @param sign_count From authenticator data
/// @param ec_signature The signature as {r, s, y_parity}
/// @param sha256_implementation The implementation of the sha256 hash
#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnSignature {
    cross_origin: bool,
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

    // If user verification is required for this signature, verify that the User Verified bit of the flags in authData
    // is set.
    assert!((flags & 0b00000100) == 0b00000100, "webauthn/unverified-user");
    // Allowing attested credential data and extension data if present
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
/// Encoding spec: https://www.w3.org/TR/webauthn/#clientdatajson-verification
// TODO Try all optimize no format!
// TODO Try origin as ByteArray
fn encode_client_data_json(hash: felt252, signature: WebauthnSignature, mut origin: Span<u8>) -> @ByteArray {
    let mut origin_as_byte_array = "";
    while let Option::Some(byte) = origin.pop_front() {
        origin_as_byte_array.append_byte(*byte);
    };

    let mut json_outro = "";
    if !signature.client_data_json_outro.is_empty() {
        assert!(*signature.client_data_json_outro[0] == ',', "webauthn/invalid-json-outro");
        let mut client_data_json_outro = signature.client_data_json_outro;
        while let Option::Some(byte) = client_data_json_outro.pop_front() {
            json_outro.append_byte(*byte);
        };
        signature.client_data_json_outro;
    } else {
        json_outro.append_byte('}');
    }
    @format!(
        "{{\"type\":\"webauthn.get\",\"challenge\":\"{}02\",\"origin\":\"{}\",\"crossOrigin\":{}{}",
        hash,
        origin_as_byte_array,
        signature.cross_origin,
        json_outro
    )
}

fn encode_authenticator_data(signature: WebauthnSignature, rp_id_hash: u256) -> Array<u8> {
    // let mut bytes = u256_to_u8s(rp_id_hash);
    // let mut authenticator_data = "";
    // while let Option::Some(byte) = bytes.pop_front() {
    //     authenticator_data.append_byte(byte);
    // };
    // authenticator_data.append_byte(signature.flags);
    // authenticator_data.append_byte(0);
    // authenticator_data.append_byte(0);
    // authenticator_data.append_byte(0);
    // authenticator_data.append_byte(signature.sign_count.try_into().unwrap());
    // authenticator_data
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
    let mut client_data = u32s_to_u8s(compute_sha256_byte_array(client_data_json).span());

    let mut arr = encode_authenticator_data(signature, signer.rp_id_hash.into());
    while let Option::Some(byte) = client_data.pop_front() {
        arr.append(*byte);
    };

    let mut word_arr: Array<u32> = array![];
    let len = arr.len();
    let rem = len % 4;
    let mut index = 0;
    let rounded_len = len - rem;
    while index != rounded_len {
        let word = (*arr.at(index + 3)).into()
            + (*arr.at(index + 2)).into() * 0x100
            + (*arr.at(index + 1)).into() * 0x10000
            + (*arr.at(index)).into() * 0x1000000;
        word_arr.append(word);
        index = index + 4;
    };
    let last = match rem {
        0 => 0_u32,
        1 => (*arr.at(len - 1)).into(),
        2 => (*arr.at(len - 1)).into() + (*arr.at(len - 2)).into() * 0x100,
        _ => (*arr.at(len - 1)).into() + (*arr.at(len - 2)).into() * 0x100 + (*arr.at(len - 3)).into() * 0x10000,
    };

    u32s_to_u256(compute_sha256_u32_array(word_arr, last, rem).span())
}

fn u32s_to_u256(arr: Span<u32>) -> u256 {
    assert!(arr.len() == 8, "u32s_to_u2562: input must be 8 elements long");
    let low: u128 = (*arr[7]).into()
        + (*arr[6]).into() * 0x1_0000_0000
        + (*arr[5]).into() * 0x1_0000_0000_0000_0000
        + (*arr[4]).into() * 0x1_0000_0000_0000_0000_0000_0000;
    let low = low.try_into().expect('u32s_to_u2562:overflow-low');
    let high = (*arr[3]).into()
        + (*arr[2]).into() * 0x1_0000_0000
        + (*arr[1]).into() * 0x1_0000_0000_0000_0000
        + (*arr[0]).into() * 0x1_0000_0000_0000_0000_0000_0000;
    let high = high.try_into().expect('u32s_to_u2562:overflow-high');
    u256 { high, low }
}

fn u32s_to_u8s(mut words: Span<u32>) -> Span<u8> {
    let mut output = array![];
    while let Option::Some(word) = words.pop_front() {
        let word: u32 = *word;
        let (rest, byte_4) = integer::u32_safe_divmod(word, 0x100);
        let (rest, byte_3) = integer::u32_safe_divmod(rest, 0x100);
        let (byte_1, byte_2) = integer::u32_safe_divmod(rest, 0x100);
        output.append(byte_1.try_into().unwrap());
        output.append(byte_2.try_into().unwrap());
        output.append(byte_3.try_into().unwrap());
        output.append(byte_4.try_into().unwrap());
    };
    output.span()
}
