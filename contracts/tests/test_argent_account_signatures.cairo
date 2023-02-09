use array::ArrayTrait;
use contracts::ArgentAccount;

const message_hash: felt = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

const signer_pubkey: felt = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_r: felt = 0x6ff7b413a8457ef90f326b5280600a4473fef49b5b1dcdfcd7f42ca7aa59c69;
const signer_s: felt = 0x23a9747ed71abc5cb956c0df44ee8638b65b3e9407deade65de62247b8fd77;

const guardian_pubkey: felt = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const guardian_r: felt = 0x1734f5510c8b862984461d2221411d12a706140bae629feac0aad35f4d91a19;
const guardian_s: felt = 0x75c904c1969e5b2bf2e9fedb32d6180f06288d81a6a2164d876ea4be2ae7520;

const guardian_backup_pubkey: felt =
    0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;
const guardian_backup_r: felt = 0x1e03a158a4142532f903caa32697a74fcf5c05b762bb866cec28670d0a53f9a;
const guardian_backup_s: felt = 0x74be76fe620a42899bc34afce7b31a058408b23c250805054fca4de4e0121ca;

fn single_signature(r: felt, s: felt) -> Array::<felt> {
    let mut signatures = ArrayTrait::new();
    signatures.append(r);
    signatures.append(s);
    signatures
}

fn double_signature(r1: felt, s1: felt, r2: felt, s2: felt) -> Array::<felt> {
    let mut signatures = ArrayTrait::new();
    signatures.append(r1);
    signatures.append(s1);
    signatures.append(r2);
    signatures.append(s2);
    signatures
}

#[test]
#[available_gas(2000000)]
fn valid_no_guardian() {
    ArgentAccount::initialize(signer_pubkey, 0, 0);
    let mut signatures = single_signature(signer_r, signer_s);
    assert(ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn valid_with_guardian() {
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, 0);
    let mut signatures = double_signature(signer_r, signer_s, guardian_r, guardian_s);
    assert(ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn valid_with_guardian_backup() {
    ArgentAccount::initialize(signer_pubkey, 1, guardian_backup_pubkey);
    let mut signatures = double_signature(signer_r, signer_s, guardian_backup_r, guardian_backup_s);
    assert(ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_hash() {
    ArgentAccount::initialize(signer_pubkey, 0, 0);
    let mut signatures = single_signature(signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(ref signatures, 0), 'invalid signature');
    assert(!ArgentAccount::is_valid_signature(ref signatures, 123), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_signer_no_guardian() {
    ArgentAccount::initialize(signer_pubkey, 0, 0);
    let mut signatures = single_signature(0, 0);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = single_signature(42, 99);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = single_signature(guardian_r, guardian_s);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_signer_with_guardian() {
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, 0);
    let mut signatures = double_signature(0, 0, 0, 0);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = double_signature(42, 99, 534, 123);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = double_signature(signer_r, signer_s, 0, 0);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = double_signature(signer_r, signer_s, signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = double_signature(guardian_r, guardian_s, guardian_r, guardian_s);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_guardian() {
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, 0);
    let mut signatures = double_signature(0, 0, 0, 0);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = double_signature(42, 99, 534, 123);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = double_signature(signer_r, signer_s, 0, 0);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = double_signature(signer_r, signer_s, signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
    let mut signatures = double_signature(guardian_r, guardian_s, guardian_r, guardian_s);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn invalid_signature_length_no_guardian() {
    ArgentAccount::initialize(signer_pubkey, 0, 0);
    let mut signatures = ArrayTrait::new();
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn invalid_signature_length_no_guardian_2() {
    ArgentAccount::initialize(signer_pubkey, 0, 0);
    let mut signatures = double_signature(signer_r, signer_s, guardian_r, guardian_s);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn invalid_signature_length_with_guardian() {
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, 0);
    let mut signatures = ArrayTrait::new();
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn invalid_signature_length_with_guardian_2() {
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, 0);
    let mut signatures = single_signature(signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(ref signatures, message_hash), 'invalid signature');
}
