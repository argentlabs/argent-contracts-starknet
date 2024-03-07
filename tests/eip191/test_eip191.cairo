use argent::signer::eip191::{calculate_eip191_hash, is_valid_eip191_signature};
use argent::signer::signer_signature::{SignerSignature, SignerSignatureTrait, Eip191Signer, Secp256k1Signature};
use starknet::eth_address::{EthAddress};
use super::super::setup::constants::{ETH_ADDRESS, ETH_SIGNER_SIG, tx_hash};
use starknet::SyscallResultTrait;
use starknet::secp256k1::{Secp256k1Point, Secp256k1PointImpl};


#[test]
fn test_eip_191_hashing() {
    let hash_result = calculate_eip191_hash(tx_hash);
    assert(hash_result == 48405440187118761992760719389369972157723609501777497852552048540887957431744, 'invalid');
}

#[test]
fn test_eip_191_verification() {
    // println!("ETH_ADDRESS: {:?}", ETH_ADDRESS());
    let (eth_address, _) = ETH_ADDRESS().get_coordinates().unwrap_syscall();
    let eth_address_felt: felt252 = eth_address.try_into().unwrap();
    let eth_address_str = EthAddress { address: eth_address_felt};
    // let sig = SignerSignature::Eip191(
    //     (Eip191Signer { eth_address: eth_address_str }, Secp256k1Signature { r: ETH_SIGNER_SIG().r, s: ETH_SIGNER_SIG().s, y_parity: false })
    // );
    // let validation_result = sig.is_valid_signature(tx_hash);
    // assert(validation_result, 'invalid-verification');
}
