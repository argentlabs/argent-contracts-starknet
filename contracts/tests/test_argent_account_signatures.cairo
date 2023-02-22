use array::ArrayTrait;
use contracts::ArgentAccount;

use contracts::tests::Signature;
use contracts::tests::signer;
use contracts::tests::guardian;
use contracts::tests::guardian_backup;
use contracts::tests::initialize_account;
use contracts::tests::initialize_account_without_guardian;

const message_hash: felt = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;


fn signature_for_signer(sign: Signature) -> Array::<felt> {
    single_signature(sign.r, sign.s)
}

fn single_signature(r: felt, s: felt) -> Array::<felt> {
    let mut signatures = ArrayTrait::new();
    signatures.append(r);
    signatures.append(s);
    signatures
}

fn signature_for_signers(sign1: Signature, sign2: Signature) -> Array::<felt> {
    double_signature(sign1.r, sign1.s, sign2.r, sign2.s)
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
    let signatures = signature_for_signer(signer());
    assert(ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}
#[test]
#[available_gas(2000000)]
fn valid_with_guardian() {
    initialize_account();
    let signatures = signature_for_signers(signer(), guardian());
    assert(ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn valid_with_guardian_backup() {
    ArgentAccount::initialize(signer().pubkey, 1, guardian_backup().pubkey);
    let signatures = signature_for_signers(signer(), guardian_backup());
    assert(ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_hash_1() {
    initialize_account_without_guardian();
    let signatures = signature_for_signer(signer());
    assert(!ArgentAccount::is_valid_signature(0, signatures), 'invalid signature');
}

#[test]
#[available_gas(2000000)]
fn invalid_hash_2() {
    initialize_account_without_guardian();
    let signatures = signature_for_signer(signer());
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
    let signatures = signature_for_signer(guardian());
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
    let signatures = double_signature(signer().r, signer().s, 0, 0);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = signature_for_signers(signer(), signer());
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = signature_for_signers(guardian(), guardian());
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
    let signatures = double_signature(signer().r, signer().s, 0, 0);
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = signature_for_signers(signer(), signer());
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
    let signatures = signature_for_signers(guardian(), guardian());
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
    let signatures = signature_for_signers(signer(), guardian());
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
    let signatures = signature_for_signer(signer());
    assert(!ArgentAccount::is_valid_signature(message_hash, signatures), 'invalid signature');
}
