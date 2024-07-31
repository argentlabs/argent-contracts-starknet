use alexandria_encoding::base64::Base64UrlEncoder;
use argent::signer::signer_signature::{WebauthnSigner};
use argent::signer::webauthn::{WebauthnSignature, Sha256Implementation, u256_to_u8s};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{SpanU8TryIntoU256, SpanU8TryIntoFelt252};
use core::sha256::{compute_sha256_byte_array, compute_sha256_u32_array};

// TODO Also try with compute_sha256_u32_array()
fn get_webauthn_hash_syscall(hash: felt252, signer: WebauthnSigner, signature: WebauthnSignature) -> u256 {
    let client_data_json = encode_client_data_json(hash, signature, signer.origin);
    let client_data_hash = compute_sha256_byte_array(client_data_json).span();
    let mut message = encode_authenticator_data(signature, signer.rp_id_hash.into());
    message.append_all(u32s_to_u8s(client_data_hash));
    let mut message_as_byte_array: ByteArray = "";
    while let Option::Some(byte) = message.pop_front() {
        message_as_byte_array.append_byte(byte);
    };
    let x: Span<u32> = compute_sha256_byte_array(@message_as_byte_array).span();
    u32s_to_u256(x)
}

/// Example JSON:
/// {"type":"webauthn.get","challenge":"3q2-7_8","origin":"http://localhost:5173","crossOrigin":false}
/// Spec: https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata
/// Encoding spec: https://www.w3.org/TR/webauthn/#clientdatajson-verification
fn encode_client_data_json(hash: felt252, signature: WebauthnSignature, origin: Span<u8>) -> @ByteArray {
    let challenge = encode_challenge(hash, signature.sha256_implementation);
    let res = format!(
        "{{\"type\":\"webauthn.get\",\"challenge\":\"{}\",\"origin\":\"http://localhost:5173\",\"crossOrigin\":false}}",
        challenge
    );
    @res
}

fn encode_challenge(hash: felt252, sha256_implementation: Sha256Implementation) -> @ByteArray {
    let mut bytes: ByteArray = format!("{}02", hash);
    // assert!(
    //     bytes.len() == 78, "webauthn2/invalid-challenge-length {}", bytes.len()
    // ); // remove '=' signs if this assert fails
    @bytes
}

fn encode_authenticator_data(signature: WebauthnSignature, rp_id_hash: u256) -> Array<u8> {
    let mut bytes = u256_to_u8s(rp_id_hash);
    bytes.append(signature.flags);
    bytes.append_all(u32s_to_u8s(array![signature.sign_count.into()].span()));
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
        let word: u32 = (*word).try_into().unwrap();
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
