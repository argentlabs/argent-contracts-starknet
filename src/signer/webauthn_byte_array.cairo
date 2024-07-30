use argent::signer::signer_signature::{WebauthnSigner};
use argent::signer::webauthn::{WebauthnSignature, Sha256Implementation};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{SpanU8TryIntoU256, SpanU8TryIntoFelt252};
use core::sha256::{compute_sha256_byte_array, compute_sha256_u32_array};

// TODO Also try with compute_sha256_u32_array()
fn get_webauthn_hash_syscall(hash: felt252, signer: WebauthnSigner, signature: WebauthnSignature) -> u256 {
    let client_data_json = encode_client_data_json_byte_array(hash, signature, signer.origin);
    let client_data_hash = compute_sha256_byte_array(client_data_json).span();
    let mut message = encode_authenticator_data(signature, signer.rp_id_hash.into());
    message.append_all(client_data_hash);
    let x: Span<u32> = compute_sha256_u32_array(message, 0, 0).span();
    u32s_to_u256(x)
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
/// Encoding spec: https://www.w3.org/TR/webauthn/#clientdatajson-verification
fn encode_client_data_json_byte_array(hash: felt252, signature: WebauthnSignature, origin: Span<u8>) -> @ByteArray {
    let mut json: ByteArray = "{\"type\":\"webauthn.get\",\"challenge\":\"";
    json.append(encode_challenge(hash, signature.sha256_implementation));
    json.append(@"\"origin\":\"");
    let mut origin = origin;
    // json.append(origin.into());
    while let Option::Some(byte) = origin.pop_front() {
        json.append_byte(*byte);
    };

    json.append(@"\"crossOrigin\":\"");
    if signature.cross_origin {
        json.append(@"true");
    } else {
        json.append(@"false");
    }
    if !signature.client_data_json_outro.is_empty() {
        assert!(*signature.client_data_json_outro.at(0) == ',', "webauthn/invalid-json-outro");
        // json.append(signature.client_data_json_outro.into());
        let mut client_data_json_outro = signature.client_data_json_outro;
        while let Option::Some(byte) = client_data_json_outro.pop_front() {
            json.append_byte(*byte);
        };
    } else {
        json.append(@"}");
    }
    @json
}

fn encode_challenge(hash: felt252, sha256_implementation: Sha256Implementation) -> @ByteArray {
    let mut bytes: ByteArray = format!("{}", hash);
    match sha256_implementation {
        Sha256Implementation::Cairo0 => panic!("Nope"),
        Sha256Implementation::Cairo1 => panic!("Nope"),
        Sha256Implementation::Syscall => (),
    };
    bytes.append(@"2");
    assert!(bytes.len() == 33, "webauthn/invalid-challenge-length"); // remove '=' signs if this assert fails
    @bytes
}

fn encode_authenticator_data(signature: WebauthnSignature, rp_id_hash: u256) -> Array<u32> {
    let mut bytes = u256_to_u32s(rp_id_hash);
    bytes.append(signature.flags.into());
    bytes.append_all(array![signature.sign_count.into()].span());
    bytes
}

fn u256_to_u32s(word: u256) -> Array<u32> {
    let (rest, part_8) = integer::u128_safe_divmod(word.low, 0x1_0000_0000);
    let (rest, part_7) = integer::u128_safe_divmod(rest, 0x1_0000_0000);
    let (part_5, part_6) = integer::u128_safe_divmod(rest, 0x1_0000_0000);
    let (rest, part_4) = integer::u128_safe_divmod(word.high, 0x1_0000_0000);
    let (rest, part_3) = integer::u128_safe_divmod(rest, 0x1_0000_0000);
    let (part_1, part_2) = integer::u128_safe_divmod(rest, 0x1_0000_0000);
    array![
        part_1.try_into().unwrap(),
        part_2.try_into().unwrap(),
        part_3.try_into().unwrap(),
        part_4.try_into().unwrap(),
        part_5.try_into().unwrap(),
        part_6.try_into().unwrap(),
        part_7.try_into().unwrap(),
        part_8.try_into().unwrap(),
    ]
}


fn u32s_to_u256(arr: Span<u32>) -> u256 {
    assert!(arr.len() == 8, "u32s_to_u256: input must be 8 elements long");
    let low: u128 = (*arr[7]).into()
        + (*arr[6]).into() * 0x1_0000_0000
        + (*arr[5]).into() * 0x1_0000_0000_0000_0000
        + (*arr[4]).into() * 0x1_0000_0000_0000_0000_0000_0000;
    let low = low.try_into().expect('u32s_to_u256:overflow-low');
    let high = (*arr[3]).into()
        + (*arr[2]).into() * 0x1_0000_0000
        + (*arr[1]).into() * 0x1_0000_0000_0000_0000
        + (*arr[0]).into() * 0x1_0000_0000_0000_0000_0000_0000;
    let high = high.try_into().expect('u32s_to_u256:overflow-high');
    u256 { high, low }
}
