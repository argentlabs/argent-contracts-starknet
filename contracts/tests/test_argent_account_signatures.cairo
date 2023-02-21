use array::ArrayTrait;
use contracts::ArgentAccount;

use contracts::tests::initialize_account;
use contracts::tests::initialize_account_without_guardian;

use contracts::tests::signer_pubkey;
use contracts::tests::signer_r;
use contracts::tests::signer_s;
use contracts::tests::guardian_pubkey;
use contracts::tests::guardian_r;
use contracts::tests::guardian_s;
use contracts::tests::guardian_backup_pubkey;
use contracts::tests::guardian_backup_r;
use contracts::tests::guardian_backup_s;

const message_hash: felt = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;


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
    initialize_account_without_guardian();
    let signatures = single_signature(signer_r, signer_s);
    assert(ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}
#[test]
#[available_gas(2000000)]
fn valid_with_guardian() {
    initialize_account();
    let signatures = double_signature(signer_r, signer_s, guardian_r, guardian_s);
    assert(ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn valid_with_guardian_backup() {
    ArgentAccount::initialize(signer_pubkey, 1, guardian_backup_pubkey);
    let signatures = double_signature(signer_r, signer_s, guardian_backup_r, guardian_backup_s);
    assert(ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_hash_1() {
    initialize_account_without_guardian();
    let signatures = single_signature(signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(0, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_hash_2() {
    initialize_account_without_guardian();
    let signatures = single_signature(signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(123, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_signer_no_guardian() {
    initialize_account_without_guardian();
    let signatures = single_signature(0, 0);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = single_signature(42, 99);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = single_signature(guardian_r, guardian_s);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_signer_with_guardian() {
    initialize_account();
    let signatures = double_signature(0, 0, 0, 0);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = double_signature(42, 99, 534, 123);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = double_signature(signer_r, signer_s, 0, 0);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = double_signature(signer_r, signer_s, signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = double_signature(guardian_r, guardian_s, guardian_r, guardian_s);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_guardian() {
    initialize_account();
    let signatures = double_signature(0, 0, 0, 0);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = double_signature(42, 99, 534, 123);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = double_signature(signer_r, signer_s, 0, 0);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = double_signature(signer_r, signer_s, signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = double_signature(guardian_r, guardian_s, guardian_r, guardian_s);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn invalid_signature_length_no_guardian() {
    initialize_account_without_guardian();
    let signatures = ArrayTrait::new();
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn invalid_signature_length_no_guardian_2() {
    initialize_account_without_guardian();
    let signatures = double_signature(signer_r, signer_s, guardian_r, guardian_s);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn invalid_signature_length_with_guardian() {
    initialize_account();
    let signatures = ArrayTrait::new();
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
#[should_panic]
fn invalid_signature_length_with_guardian_2() {
    initialize_account();
    let signatures = single_signature(signer_r, signer_s);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}
