use array::ArrayTrait;
use contracts::ArgentAccount;

const message_hash: felt = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

const signer_pubkey: felt = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_r: felt = 0x6ff7b413a8457ef90f326b5280600a4473fef49b5b1dcdfcd7f42ca7aa59c69;
const signer_s: felt = 0x23a9747ed71abc5cb956c0df44ee8638b65b3e9407deade65de62247b8fd77;

const guardian_pubkey: felt = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const guardian_r: felt = 0x1734f5510c8b862984461d2221411d12a706140bae629feac0aad35f4d91a19;
const guardian_s: felt = 0x75c904c1969e5b2bf2e9fedb32d6180f06288d81a6a2164d876ea4be2ae7520;

const guardian_backup_pubkey: felt = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;
const guardian_backup_r: felt = 0x1e03a158a4142532f903caa32697a74fcf5c05b762bb866cec28670d0a53f9a;
const guardian_backup_s: felt = 0x74be76fe620a42899bc34afce7b31a058408b23c250805054fca4de4e0121ca;

#[test]
#[available_gas(20000)]
fn valid_no_guardian() {
    let mut signatures = ArrayTrait::new();
    signatures.append(signer_r);
    signatures.append(signer_s);
    ArgentAccount::initialize(signer_pubkey, 0, 0);
    assert(ArgentAccount::isValidSignature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(20000)]
fn valid_with_guardian() {
    let mut signatures = ArrayTrait::new();
    signatures.append(signer_r);
    signatures.append(signer_s);
    signatures.append(guardian_r);
    signatures.append(guardian_s);
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, 0);
    assert(ArgentAccount::isValidSignature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(20000)]
fn valid_with_guardian_backup() {
    let mut signatures = ArrayTrait::new();
    signatures.append(signer_r);
    signatures.append(signer_s);
    signatures.append(guardian_backup_r);
    signatures.append(guardian_backup_s);
    ArgentAccount::initialize(signer_pubkey, 1, guardian_backup_pubkey);
    assert(ArgentAccount::isValidSignature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(20000)]
fn invalid_signer_signature() {
    let mut signatures = ArrayTrait::new();
    signatures.append(42);
    signatures.append(49);
    ArgentAccount::initialize(signer_pubkey, 0, 0);
    assert(!ArgentAccount::isValidSignature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(20000)]
fn invalid_signer_hash() {
    let mut signatures = ArrayTrait::new();
    signatures.append(signer_r);
    signatures.append(signer_s);
    ArgentAccount::initialize(signer_pubkey, 0, 0);
    assert(!ArgentAccount::isValidSignature(ref signatures, 123), 'invalid signature');
}
