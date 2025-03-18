use argent::signer::signer_signature::{
    Ed25519Signer, Ed25519Signature, SignerSignature, SIWSSignature,
};
use argent::signer::siws::{is_valid_siws_signature};
use core::traits::TryInto;

#[test]
fn test_siws_signature_validation() {
    // === SIWS Test Values ===

    // Public Key (Base58): 24KebvJCscDwVm5KDMF3BJzZ8F6NqXpPUGGVC9Nz1bG6
    // Public Key (Hex): 0x0fb583db624d09d8e19a8a5bc33176a5005f3d4dd496d762630e07a320af0c63
    // Secret Key (Hex):
    // 0x5652db16072844eaf9d0795d3d2a7a58fd98c600df6f535ea60768c14a9a10a60fb583db624d09d8e19a8a5bc33176a5005f3d4dd496d762630e07a320af0c63

    // Message:
    // https://example.com wants you to sign in with your Solana account:
    // 24KebvJCscDwVm5KDMF3BJzZ8F6NqXpPUGGVC9Nz1bG6

    // Authorize Controller session with hash: 0x1234567890abcdef

    // Message Bytes (Hex):
    // 0x68747470733a2f2f6578616d706c652e636f6d2077616e747320796f7520746f207369676e20696e207769746820796f757220536f6c616e61206163636f756e743a0a32344b6562764a4373634477566d354b444d4633424a7a5a3846364e715870505547475643394e7a316247360a0a417574686f72697a6520436f6e74726f6c6c65722073657373696f6e207769746820686173683a20307831323334353637383930616263646566

    // Signature (Base58):
    // 5xFDgX19fmWMPK8R7pLPR5WtPUPuarYKPxLbZdU4TUZ8KVSvgDX5aDwEy1EySHN1ipDNf2xTQc69cs6tWXc7mFJM
    // Signature r (Hex): 0xf7b595899ccc59a4ebf356147a1f75b14ca6481cf565277ed2f62605fa744700
    // Signature s (Hex): 0x25ac25b60801c292ef7834cb4a86f2f92c22b67e394e29a9f807fe3065f5bf06
    let pubkey: u256 = 0x0fb583db624d09d8e19a8a5bc33176a5005f3d4dd496d762630e07a320af0c63;
    let domain: Span<u8> = array![
        'h',
        't',
        't',
        'p',
        's',
        ':',
        '/',
        '/',
        'e',
        'x',
        'a',
        'm',
        'p',
        'l',
        'e',
        '.',
        'c',
        'o',
        'm',
    ]
        .span();
    let hash: felt252 = 0x1234567890abcdef;
    let signer = Ed25519Signer { pubkey: pubkey.try_into().expect('ed25519 zero') };
    let signature = SIWSSignature {
        domain,
        signature: Ed25519Signature {
            r: 0xf7b595899ccc59a4ebf356147a1f75b14ca6481cf565277ed2f62605fa744700,
            s: 0x25ac25b60801c292ef7834cb4a86f2f92c22b67e394e29a9f807fe3065f5bf06,
        },
    };

    assert(is_valid_siws_signature(hash, signer, signature), 'Statement validation failed');
}
