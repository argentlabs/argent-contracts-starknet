use argent::signer::signer_signature::{WebauthnSigner};
use argent::signer::signer_signature::{is_valid_webauthn_signature};
use argent::signer::webauthn::{WebauthnAssertion, Sha256Implementation};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{
    ByteArrayExt, SpanU8TryIntoU256, SpanU8TryIntoFelt252, u32s_to_u256, u32s_to_u8s, u256_to_u8s
};
use starknet::SyscallResultTrait;
use starknet::secp256_trait::Signature;
use starknet::{EthAddress, eth_signature::{Signature as Secp256k1Signature, is_eth_signature_valid}};

fn new_webauthn_signer(origin: ByteArray, rp_id_hash: u256, pubkey: u256) -> WebauthnSigner {
    let origin = origin.into_bytes().span();
    let rp_id_hash = rp_id_hash.try_into().expect('argent/zero-rp-id-hash');
    let pubkey = pubkey.try_into().expect('argent/zero-pubkey');
    WebauthnSigner { origin, rp_id_hash, pubkey }
}

fn localhost_rp() -> (ByteArray, u256) {
    let origin = "http://localhost:5173";
    let rp_id_hash = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763;
    (origin, rp_id_hash)
}

#[test]
fn test_is_valid_webauthn_signature() {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x06fd6673287ba2e4d2975ad878dc26c0a989c549259d87a044a8d37bb9168bb4;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let assertion = WebauthnAssertion {
        cross_origin: false,
        client_data_json_outro: array![].span(),
        flags: 0b00000101,
        sign_count: 0,
        signature: Signature {
            r: 0x27b78470673308c9e7ef6d9cb4fbf74b892f9e3826b515333d721cb8385cfb72,
            s: 0x35c7ae175d75e09b1907f4232c88bfd69b7c9d7f32b4b2d392a6a95324a61f21,
            y_parity: true,
        },
        sha256_implementation: Sha256Implementation::Cairo1,
    };

    let is_valid = is_valid_webauthn_signature(transaction_hash, signer, assertion);
    assert!(is_valid, "invalid");
}
