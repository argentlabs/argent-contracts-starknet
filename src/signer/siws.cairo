use alexandria_encoding::base58::Base58Encoder;
use argent::signer::signer_signature::{Ed25519Signer, SIWSSignature, is_valid_ed25519_signature};
use argent::utils::bytes::{
    u256_to_u8s, u32s_typed_to_u256, ArrayU8Ext, ByteArrayExt, u32s_to_byte_array,
    u256_to_byte_array,
};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::hashing::poseidon_2;
use core::serde::Serde;
use core::hash::{HashStateTrait, HashStateExTrait};
use core::byte_array::{ByteArrayTrait, ByteArray};
use core::sha256::compute_sha256_byte_array;
use starknet::secp256_trait::{is_signature_entry_valid};

/// @notice Verifies a Sign In With Solana signature
/// @param hash The hash/challenge to verify
/// @param signer The Ed25519 signer with the public key
/// @param signature The SIWS signature containing domain, statement and Ed25519 signature
/// @return True if the signature is valid, false otherwise
#[inline(always)]
fn is_valid_siws_signature(hash: felt252, signer: Ed25519Signer, signature: SIWSSignature) -> bool {
    // Reconstruct the message in the format:
    // ${domain} wants you to sign in with your Solana account:
    // ${address}
    //
    // ${statement}

    // let domain_bytes: ByteArray = domain.into();
    let address_bytes = u256_to_u8s(signer.pubkey.into());
    let address_b58 = Base58Encoder::encode(address_bytes);
    let address_b58_bytes = address_b58.span().into_byte_array();
    let message = format!(
        "{} wants you to sign in with your Solana account:\n{}\n\nAuthorize Controller session with hash: 0x{:x}",
        signature.domain.into_byte_array(),
        address_b58_bytes,
        hash,
    );

    // Verify the signature using the Ed25519 verification
    let pubkey: u256 = signer.pubkey.into();
    let signature = array![signature.signature.r, signature.signature.s];
    alexandria_math::ed25519::verify_signature(
        message.into_bytes().span(), signature.span(), pubkey,
    )
}
