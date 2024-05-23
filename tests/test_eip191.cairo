use argent::signer::eip191::{calculate_eip191_hash, is_valid_eip191_signature};
use argent::signer::signer_signature::{SignerSignature, SignerSignatureTrait, Eip191Signer, Secp256Signature};
use super::setup::constants::{tx_hash};

const eth_address: felt252 = 0x3da5e1F7B6D63E9982A6c26D8eCFd8219654E087;
const sig_r: u256 = 0x944254ac8d2d6019987a58302f531eda7161fe3703bebfaa1a6f9bd82e9e7832;
const sig_s: u256 = 0x58cb979aaac276bc59f2858b3dc6cdd1e31b401434bfc12fc0ea4b42c83c72f1;
const sig_y_parity: bool = false;

#[test]
fn test_eip_191_hashing() {
    let hash_result = calculate_eip191_hash(tx_hash);
    assert_eq!(hash_result, 48405440187118761992760719389369972157723609501777497852552048540887957431744, "invalid");
}

#[test]
fn test_eip_191_verification() {
    let sig = SignerSignature::Eip191(
        (
            Eip191Signer { eth_address: eth_address.try_into().unwrap(), },
            Secp256Signature { r: sig_r, s: sig_s, y_parity: sig_y_parity }
        )
    );
    let validation_result = sig.is_valid_signature(tx_hash);
    assert!(validation_result, "invalid-verification");
}
