use argent::utils::serialization::serialize;
use crate::{
    ArgentAccountSetup, ArgentAccountWithoutGuardianSetup, ITestArgentAccountDispatcherTrait, SignerKeyPairImpl,
    StarknetKeyPair, initialize_account, initialize_account_without_guardian,
};
use snforge_std::{generate_random_felt};
use starknet::VALIDATED;

#[test]
fn valid_no_guardian() {
    let ArgentAccountWithoutGuardianSetup { account, owners } = initialize_account_without_guardian();
    let tx_hash = generate_random_felt();
    let owner_signature = owners[0].sign(tx_hash);
    let is_valid = account.is_valid_signature(tx_hash, serialize(@array![owner_signature]));
    assert_eq!(is_valid, VALIDATED);
}

#[test]
fn valid_with_guardian() {
    let ArgentAccountSetup { account, owners, guardians, .. } = initialize_account();
    let tx_hash = generate_random_felt();
    let owner_signature = owners[0].sign(tx_hash);
    let guardian_signature = guardians[0].sign(tx_hash);
    let is_valid = account.is_valid_signature(tx_hash, serialize(@array![owner_signature, guardian_signature]));
    assert_eq!(is_valid, VALIDATED);
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn invalid_hash() {
    let ArgentAccountWithoutGuardianSetup { account, owners } = initialize_account_without_guardian();
    let tx_hash = generate_random_felt();
    let owner_signature = owners[0].sign(tx_hash);
    account.is_valid_signature(0, serialize(@array![owner_signature]));
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn invalid_owner_without_guardian() {
    let ArgentAccountWithoutGuardianSetup { account, .. } = initialize_account_without_guardian();
    let tx_hash = generate_random_felt();
    let random_valid_signature = StarknetKeyPair::random().sign(tx_hash);
    account.is_valid_signature(tx_hash, serialize(@array![random_valid_signature]));
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn invalid_owner_with_guardian() {
    let ArgentAccountSetup { account, guardians, .. } = initialize_account();
    let tx_hash = generate_random_felt();
    let guardian_signature = guardians[0].sign(tx_hash);
    let random_valid_signature = StarknetKeyPair::random().sign(tx_hash);
    account.is_valid_signature(tx_hash, serialize(@array![random_valid_signature, guardian_signature]));
}

#[test]
#[should_panic(expected: ('argent/invalid-guardian-sig',))]
fn valid_owner_with_invalid_guardian() {
    let ArgentAccountSetup { account, owners, .. } = initialize_account();
    let tx_hash = generate_random_felt();
    let owner_signature = owners[0].sign(tx_hash);
    let random_valid_signature = StarknetKeyPair::random().sign(tx_hash);
    account.is_valid_signature(tx_hash, serialize(@array![owner_signature, random_valid_signature]));
}

#[test]
#[should_panic(expected: ('argent/invalid-owner-sig',))]
fn invalid_owner_with_invalid_guardian() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    let tx_hash = generate_random_felt();
    let random_valid_signature = StarknetKeyPair::random().sign(tx_hash);
    account.is_valid_signature(tx_hash, serialize(@array![random_valid_signature, random_valid_signature]));
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn invalid_empty_signature_without_guardian() {
    let ArgentAccountWithoutGuardianSetup { account, .. } = initialize_account_without_guardian();
    let tx_hash = generate_random_felt();
    account.is_valid_signature(tx_hash, array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-guardian-sig',))]
fn invalid_signature_length_without_guardian() {
    let ArgentAccountWithoutGuardianSetup { account, owners } = initialize_account_without_guardian();
    let tx_hash = generate_random_felt();
    let owner_signature = owners[0].sign(tx_hash);
    let random_valid_signature = StarknetKeyPair::random().sign(tx_hash);
    account.is_valid_signature(tx_hash, serialize(@array![owner_signature, random_valid_signature]));
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn invalid_empty_signature_with_guardian() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    let tx_hash = generate_random_felt();
    account.is_valid_signature(tx_hash, array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-length',))]
fn invalid_empty_span_signature() {
    let ArgentAccountSetup { account, .. } = initialize_account();
    let tx_hash = generate_random_felt();
    account.is_valid_signature(tx_hash, array![0]);
}

#[test]
#[should_panic(expected: ('argent/missing-guardian-sig',))]
fn invalid_signature_length_with_guardian() {
    let ArgentAccountSetup { account, owners, .. } = initialize_account();
    let tx_hash = generate_random_felt();
    let owner_signature = owners[0].sign(tx_hash);
    account.is_valid_signature(tx_hash, serialize(@array![owner_signature]));
}
