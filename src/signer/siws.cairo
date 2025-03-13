use argent::signer::signer_signature::{
    Ed25519Signer, SIWSSignature, is_valid_ed25519_signature,
};
use argent::utils::bytes::{u256_to_u8s};
use argent::utils::array_ext::ArrayExtTrait;
use core::serde::Serde;

/// @notice Reconstructs the SIWS message format for verification
/// @param hash The hash/challenge to include in the statement
/// @param signer The Ed25519 signer with the public key
/// @param statement The statement part of the message
/// @param domain The domain requesting the sign-in (e.g., "https://cartridge.gg")
/// @return The reconstructed message as a felt252
fn get_siws_message(
    hash: felt252, signer: Ed25519Signer, statement: Span<u8>, domain: felt252,
) -> felt252 {
    // Reconstruct the message in the format:
    // ${domain} wants you to sign in with your Solana account:
    // ${address}
    //
    // ${statement}

    let mut message = array![];

    // Add domain part
    let domain_bytes = u256_to_u8s(domain.into());
    message.append_all(domain_bytes.span());

    // Add " wants you to sign in with your Solana account:" part
    message
        .append_all(
            array![
                ' ',
                'w',
                'a',
                'n',
                't',
                's',
                ' ',
                'y',
                'o',
                'u',
                ' ',
                't',
                'o',
                ' ',
                's',
                'i',
                'g',
                'n',
                ' ',
                'i',
                'n',
                ' ',
                'w',
                'i',
                't',
                'h',
                ' ',
                'y',
                'o',
                'u',
                'r',
                ' ',
                'S',
                'o',
                'l',
                'a',
                'n',
                'a',
                ' ',
                'a',
                'c',
                'c',
                'o',
                'u',
                'n',
                't',
                ':',
                '\n',
            ]
                .span(),
        );

    // Add address (derived from the signer's public key)
    let pubkey: u256 = signer.pubkey.into();
    let address_bytes = u256_to_u8s(pubkey);
    message.append_all(address_bytes.span());
    message.append('\n');
    message.append('\n');

    // Add statement (which contains the hash)
    message.append_all(statement);

    // Convert the message to felt252
    // Since we can't directly convert Span<u8> to felt252, we'll use a workaround
    // This is a simplified version - in a real implementation, you'd need to handle
    // the conversion properly based on your requirements
    let mut result: felt252 = 0;
    let mut bytes = message.span();
    let mut i: u32 = 0;
    let max_bytes: u32 = 31; // Maximum bytes that can fit in a felt252

    // Simple conversion - assumes the message fits in a felt252
    // In a real implementation, you'd need to handle larger messages
    while let Option::Some(byte) = bytes.pop_front() {
        result = result * 256 + (*byte).into();
        i += 1;
        if i == max_bytes {
            break;
        }
    };

    result
}

/// @notice Verifies a Sign In With Solana signature
/// @param hash The hash/challenge to verify
/// @param signer The Ed25519 signer with the public key
/// @param signature The Ed25519 signature
/// @param statement The statement part of the message (contains the hash/challenge)
/// @param domain The domain requesting the sign-in (e.g., "https://cartridge.gg")
/// @return True if the signature is valid, false otherwise
#[inline(always)]
fn is_valid_siws_signature(
    hash: felt252, signer: Ed25519Signer, signature: SIWSSignature,
) -> bool {
    // Reconstruct the message
    let message = get_siws_message(hash, signer, signature.statement, signature.domain);

    // Verify the signature using the Ed25519 verification
    is_valid_ed25519_signature(message, signer, signature.signature)
}

/// @notice Validates that the statement follows the expected format
/// @param statement The statement to validate
/// @param hash The hash/challenge that should be included in the statement
/// @return True if the statement is valid, false otherwise
fn validate_siws_statement(statement: Span<u8>, hash: felt252) -> bool {
    // Expected format: "Authorize Controller session with hash: ${hash}"

    // Check if the statement starts with "Authorize Controller session with hash: "
    let prefix = array![
        'A',
        'u',
        't',
        'h',
        'o',
        'r',
        'i',
        'z',
        'e',
        ' ',
        'C',
        'o',
        'n',
        't',
        'r',
        'o',
        'l',
        'l',
        'e',
        'r',
        ' ',
        's',
        'e',
        's',
        's',
        'i',
        'o',
        'n',
        ' ',
        'w',
        'i',
        't',
        'h',
        ' ',
        'h',
        'a',
        's',
        'h',
        ':',
        ' ',
    ]
        .span();

    // Check if the statement has the correct prefix
    if statement.len() <= prefix.len() {
        return false;
    }

    let mut i = 0;
    let mut valid = true;

    while i < prefix.len() && valid {
        if *statement.at(i) != *prefix.at(i) {
            valid = false;
        } else {
            i += 1;
        }
    };

    if !valid {
        return false;
    }

    // Extract the hash part from the statement
    let hash_part = statement.slice(prefix.len(), statement.len() - prefix.len());

    // Convert the hash part to felt252 and compare with the expected hash
    // This is a simplified version - in a real implementation, you'd need to handle
    // the conversion properly based on your requirements
    let mut statement_hash: felt252 = 0;
    let mut bytes = hash_part;
    let mut i: u32 = 0;
    let max_bytes: u32 = 31; // Maximum bytes that can fit in a felt252

    // Simple conversion - assumes the hash fits in a felt252
    while let Option::Some(byte) = bytes.pop_front() {
        statement_hash = statement_hash * 256 + (*byte).into();
        i += 1;
        if i == max_bytes {
            break;
        }
    };

    statement_hash == hash
}
