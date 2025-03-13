#[cfg(test)]
mod tests {
    use argent::signer::signer_signature::{
        Ed25519Signer, Ed25519Signature, SignerSignature, SIWSSignature,
    };
    use argent::signer::siws::{is_valid_siws_signature, validate_siws_statement};
    use core::traits::TryInto;

    #[test]
    fn test_siws_signature_validation() {
        // Create a test hash/challenge
        let hash: felt252 = 0x1234567890abcdef;

        // Create a test domain
        let domain: felt252 = 'https://cartridge.gg';

        // Create a test statement with the hash
        let statement = array![
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
            '0',
            'x',
            '1',
            '2',
            '3',
            '4',
            '5',
            '6',
            '7',
            '8',
            '9',
            '0',
            'a',
            'b',
            'c',
            'd',
            'e',
            'f',
        ]
            .span();

        // Test statement validation
        assert(validate_siws_statement(statement, hash), 'Statement validation failed');

        // Create a test Ed25519 signer
        let pubkey: u256 = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        let signer = Ed25519Signer { pubkey: pubkey.try_into().unwrap() };

        // Create a test Ed25519 signature
        let signature = Ed25519Signature { r: 0x1234, s: 0x5678 };

        // Create a test SIWS signer signature
        let siws_signer_signature = SIWSSignature { domain, statement, signature };

        // Create a SignerSignature enum variant for SIWS
        let _signer_signature = SignerSignature::SIWS((signer, siws_signer_signature));
    }
}
