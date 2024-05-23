use argent::signer::signer_signature::{SignerSignature, SignerSignatureTrait, Secp256r1Signer, Secp256Signature};

const message_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;
const pubkey: u256 = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
const sig_r: u256 = 0x9be81ce3b35b4bcfb271b546a00307201525a583cce2c100e0518282eaee5479;
const sig_s: u256 = 0xf945e8f0cb8630b32cfdb853c51298d4b5cdc311ee77b0e4a01f3c9e56b406f0;
const sig_y_parity: bool = false;

fn validateR1Signature(r: u256, s: u256, y_parity: bool) -> bool {
    let sig = SignerSignature::Secp256r1(
        (Secp256r1Signer { pubkey: pubkey.try_into().unwrap() }, Secp256Signature { r, s, y_parity })
    );
    sig.is_valid_signature(message_hash)
}

#[test]
fn test_successful_verification() {
    assert!(validateR1Signature(sig_r, sig_s, sig_y_parity), "invalid-verification");
}

#[test]
#[should_panic(expected: ('argent/invalid-r-value',))]
fn test_high_r() {
    validateR1Signature(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, sig_s, sig_y_parity);
}

#[test]
#[should_panic(expected: ('argent/invalid-r-value',))]
fn test_0_r() {
    validateR1Signature(0, sig_s, sig_y_parity);
}

#[test]
#[should_panic(expected: ('argent/invalid-s-value',))]
fn test_high_s() {
    validateR1Signature(sig_r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, sig_y_parity);
}

#[test]
#[should_panic(expected: ('argent/invalid-s-value',))]
fn test_0_s() {
    validateR1Signature(sig_r, 0, sig_y_parity);
}

