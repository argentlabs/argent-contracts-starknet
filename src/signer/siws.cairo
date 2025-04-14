use alexandria_encoding::base58::Base58Encoder;
use argent::signer::signer_signature::{SIWSSignature, Ed25519Signer};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{
    ArrayU8Ext, ByteArrayExt, u256_to_byte_array, u256_to_u8s, u32s_to_byte_array,
    u32s_typed_to_u256,
};
use argent::utils::hashing::poseidon_2;
use core::byte_array::{ByteArray, ByteArrayTrait};
use core::hash::{HashStateExTrait, HashStateTrait};
use core::serde::Serde;
use core::sha256::compute_sha256_byte_array;
use starknet::secp256_trait::is_signature_entry_valid;
use garaga::signatures::eddsa_25519::EdDSASignatureWithHint;

#[starknet::interface]
trait IGaragaEddsa<TContractState> {
    fn verify_eddsa(self: @TContractState, signature_with_hint: EdDSASignatureWithHint) -> bool;
}

/// @notice Verifies a Sign In With Solana signature
/// @param hash The hash/challenge to verify
/// @param signer The Ed25519Signer (EdDSA - Ed25519 curve) signer with the public key
/// @param signature The SIWS signature containing domain and Ed25519 signature with hint
/// @return True if the signature is valid, false otherwise
#[inline(always)]
fn is_valid_siws_signature(
    hash: felt252, signer: Ed25519Signer, mut siws_signature: SIWSSignature,
) -> bool {
    let address_bytes = u256_to_u8s(signer.pubkey.into());
    let address_b58 = Base58Encoder::encode(address_bytes.span());
    let address_b58_bytes = address_b58.span().into_byte_array();
    let message = format!(
        "{} wants you to sign in with your Solana account:\n{}\n\nAuthorize Controller session with hash: 0x{:x}",
        siws_signature.domain.into_byte_array(),
        address_b58_bytes,
        hash,
    );
    siws_signature.signature_with_hint.signature.msg = message.into_bytes().span();

    // Verify the signature using the Ed25519 verification with hints via library call
    let class_hash = 0x03cbed0f78d48138af06b7b3cff40ef469931dbad9ce336b3a57e781f056dc5f.try_into().unwrap();
    let dispatcher = IGaragaEddsaLibraryDispatcher { class_hash: class_hash };
    dispatcher.verify_eddsa(siws_signature.signature_with_hint)
}

#[starknet::contract]
mod GaragaEddsa {
    use garaga::signatures::eddsa_25519::{is_valid_eddsa_signature, EdDSASignatureWithHint};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl GaragaEddsaImpl of super::IGaragaEddsa<ContractState> {
        fn verify_eddsa(self: @ContractState, signature_with_hint: EdDSASignatureWithHint) -> bool {
            is_valid_eddsa_signature(signature_with_hint)
        }
    }
}
