use crate::{
    Felt252TryIntoStarknetSigner, GUARDIAN, ITestArgentAccountDispatcherTrait, OWNER, TX_HASH, WRONG_GUARDIAN,
    WRONG_OWNER, initialize_account, initialize_account_without_guardian, to_starknet_signatures,
    to_starknet_signer_signatures,
};
use starknet::VALIDATED;

#[test]
fn valid_no_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signatures(array![OWNER()]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), VALIDATED);
}

#[test]
fn valid_with_guardian() {
    let signatures = to_starknet_signatures(array![OWNER(), GUARDIAN()]);
    assert_eq!(initialize_account().is_valid_signature(TX_HASH, signatures), VALIDATED);
}

#[test]
fn invalid_hash_1() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signatures(array![OWNER()]);
    assert_eq!(account.is_valid_signature(0, signatures), 0);
}

#[test]
fn invalid_hash_2() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signatures(array![OWNER()]);
    assert_eq!(account.is_valid_signature(123, signatures), 0);
}

#[test]
fn invalid_owner_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(array![1, 2, 3]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signatures(array![WRONG_OWNER()]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
}

#[test]
fn invalid_owner_with_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![1, 2, 3, 5, 8, 8]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signatures(array![WRONG_OWNER(), GUARDIAN()]);
    account.is_valid_signature(TX_HASH, signatures);
}

#[test]
fn valid_owner_with_invalid_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![OWNER().pubkey, OWNER().sig.r, OWNER().sig.s, 1, 2, 3]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signer_signatures(array![OWNER().pubkey, OWNER().sig.r, OWNER().sig.s, 25, 42, 69]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signatures(array![OWNER(), WRONG_GUARDIAN()]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signatures(array![OWNER(), OWNER()]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
}

#[test]
fn invalid_owner_with_invalid_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![1, 2, 3, 4, 5, 6]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signer_signatures(array![2, 42, 99, 6, 534, 123]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signer_signatures(
        array![WRONG_OWNER().pubkey, WRONG_OWNER().sig.r, WRONG_OWNER().sig.s, 1, 2, 3],
    );
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signer_signatures(
        array![1, 2, 3, WRONG_GUARDIAN().pubkey, WRONG_GUARDIAN().sig.r, WRONG_GUARDIAN().sig.s],
    );
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
    let signatures = to_starknet_signatures(array![WRONG_OWNER(), WRONG_GUARDIAN()]);
    assert_eq!(account.is_valid_signature(TX_HASH, signatures), 0);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn invalid_empty_signature_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = array![];
    account.is_valid_signature(TX_HASH, signatures);
}

#[test]
#[should_panic(expected: ('argent/invalid-guardian-sig',))]
fn invalid_signature_length_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signatures(array![OWNER(), GUARDIAN()]);
    account.is_valid_signature(TX_HASH, signatures);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn invalid_empty_signature_with_guardian() {
    let account = initialize_account();
    let signatures = array![];
    account.is_valid_signature(TX_HASH, signatures);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-length',))]
fn invalid_empty_span_signature() {
    let account = initialize_account();
    account.is_valid_signature(TX_HASH, array![0]);
}

#[test]
#[should_panic(expected: ('argent/missing-guardian-sig',))]
fn invalid_signature_length_with_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signatures(array![OWNER()]);
    account.is_valid_signature(TX_HASH, signatures);
}

