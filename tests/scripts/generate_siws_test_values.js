/**
 * Sign In With Solana Test Value Generator
 * 
 * This script generates test values that can be used in the Cairo SIWS implementation.
 * It creates a keypair, constructs a SIWS message, signs it, and outputs the values
 * in a format suitable for use in Cairo tests.
 * 
 * To run this script:
 * 1. Install required dependencies: npm install @solana/web3.js tweetnacl bs58
 * 2. Run the script: node generate_siws_test_values.js
 */
import { Keypair } from '@solana/web3.js';
import nacl from 'tweetnacl';
import bs58 from 'bs58';

// Create a test keypair
function generateKeypair() {
  const keypair = Keypair.generate();
  return {
    publicKey: keypair.publicKey,
    secretKey: keypair.secretKey,
  };
}

// Convert bytes to hex string
function bytesToHex(bytes) {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

// Construct a SIWS message according to the specification
function constructSIWSMessage({ domain, publicKey, statement }) {
  return `${domain} wants you to sign in with your Solana account:
${publicKey.toBase58()}

${statement}`;
}

// Sign a message using Ed25519
function signMessage(message, secretKey) {
  const messageBytes = new TextEncoder().encode(message);
  const signature = nacl.sign.detached(messageBytes, secretKey);
  return {
    signature,
    messageBytes
  };
}

// Main function to generate and output test values
function generateTestValues() {
  // Create test inputs
  const domain = 'https://example.com';
  const { publicKey, secretKey } = generateKeypair();
  const challenge = '0x1234567890abcdef'; // Example challenge
  const statement = `Authorize Controller session with hash: ${challenge}`;

  console.log('\n=== SIWS Test Values ===\n');
  
  // Output keypair information
  console.log('Public Key (Base58):', publicKey.toBase58());
  console.log('Public Key (Hex):', '0x' + bytesToHex(publicKey.toBytes()));
  console.log('Secret Key (Hex):', '0x' + bytesToHex(secretKey));

  // Construct and output the message
  const message = constructSIWSMessage({ domain, publicKey, statement });
  console.log('\nMessage:');
  console.log(message);

  // Sign the message and output the signature
  const { signature, messageBytes } = signMessage(message, secretKey);
  console.log('\nMessage Bytes (Hex):', '0x' + bytesToHex(messageBytes));
  
  // Split the signature into r and s components for Ed25519
  // (r is the first 32 bytes, s is the last 32 bytes)
  const r = signature.slice(0, 32);
  const s = signature.slice(32, 64);
  
  console.log('\nSignature (Base58):', bs58.encode(signature));
  console.log('Signature r (Hex):', '0x' + bytesToHex(r));
  console.log('Signature s (Hex):', '0x' + bytesToHex(s));
  
  // Output values for use in Cairo tests
  console.log('\n=== Cairo Test Values ===\n');
  console.log(`let pubkey: u256 = 0x${bytesToHex(publicKey.toBytes())};`);
  console.log(`let domain: felt252 = '${domain}';`);
  console.log(`let hash: felt252 = ${challenge};`);
  console.log(`let signature = Ed25519Signature { r: 0x${bytesToHex(r)}, s: 0x${bytesToHex(s)} };`);
  
  // Output statement as array of characters for Cairo
  console.log('\nStatement array for Cairo:');
  console.log('let statement = array![');
  const statementChars = Array.from(statement);
  for (let i = 0; i < statementChars.length; i++) {
    const char = statementChars[i];
    const isLast = i === statementChars.length - 1;
    console.log(`    '${char}'${isLast ? '' : ','}`);
  }
  console.log('].span();');
}

// Run the generator
generateTestValues();