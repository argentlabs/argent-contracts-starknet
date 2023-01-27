use contracts::ArgentAccount;
use array::ArrayTrait;

const message_hash: felt = 0x503f4bea29baee10b22a7f10bdc82dda071c977c1f25b8f3973d34e6b03b2c;
const public_key: felt = 0x7b7454acbe7845da996377f85eb0892044d75ae95d04d3325a391951f35d2ec;
const signature_r: felt = 0xbe96d72eb4f94078192c2e84d5230cde2a70f4b45c8797e2c907acff5060bb;
const signature_s: felt = 0x677ae6bba6daf00d2631fab14c8acf24be6579f9d9e98f67aa7f2770e57a1f5;

#[test]
#[available_gas(20000)]
fn valid_no_guardian() {
    let mut signatures = ArrayTrait::new();
    signatures.append(signature_r);
    signatures.append(signature_s);
    ArgentAccount::initialize(public_key, 0, 0);
    assert(ArgentAccount::isValidSignature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(20000)]
fn valid_with_guardian() {
    let mut signatures = ArrayTrait::new();
    signatures.append(signature_r);
    signatures.append(signature_s);
    signatures.append(signature_r);
    signatures.append(signature_s);
    ArgentAccount::initialize(public_key, public_key, 0);
    assert(ArgentAccount::isValidSignature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(20000)]
fn valid_with_guardian_backup() {
    let mut signatures = ArrayTrait::new();
    signatures.append(signature_r);
    signatures.append(signature_s);
    signatures.append(signature_r);
    signatures.append(signature_s);
    ArgentAccount::initialize(public_key, 1, public_key);
    assert(ArgentAccount::isValidSignature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(20000)]
fn invalid_signer_signature() {
    let mut signatures = ArrayTrait::new();
    signatures.append(42);
    signatures.append(49);
    ArgentAccount::initialize(public_key, 0, 0);
    assert(!ArgentAccount::isValidSignature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(20000)]
fn invalid_signer_hash() {
    let mut signatures = ArrayTrait::new();
    signatures.append(signature_r);
    signatures.append(signature_s);
    ArgentAccount::initialize(public_key, 0, 0);
    assert(!ArgentAccount::isValidSignature(ref signatures, 123), 'invalid signature');
}
