use argent::presets::argent_account::ArgentAccount;
use argent::signer::signer_signature::{Signer, StarknetSigner, starknet_signer_from_pubkey};
use starknet::VALIDATED;
use super::setup::{
    utils::to_starknet_signer_signatures,
    constants::{
        OWNER_SIG, GUARDIAN_KEY, GUARDIAN_SIG, OWNER_KEY, GUARDIAN_BACKUP_KEY, GUARDIAN_BACKUP_SIG, WRONG_OWNER_KEY,
        WRONG_OWNER_SIG, WRONG_GUARDIAN_SIG, WRONG_GUARDIAN_KEY, message_hash
    },
    account_test_setup::{
        ITestArgentAccountDispatcher, ITestArgentAccountDispatcherTrait, initialize_account,
        initialize_account_without_guardian, initialize_account_with
    }
};

#[test]
fn valid_no_guardian() {
    let signatures = to_starknet_signer_signatures(array![OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s]);
    assert(
        initialize_account_without_guardian().is_valid_signature(message_hash, signatures) == VALIDATED,
        'invalid signature'
    );
}

#[test]
fn valid_with_guardian() {
    let signatures = to_starknet_signer_signatures(
        array![OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s, GUARDIAN_KEY(), GUARDIAN_SIG().r, GUARDIAN_SIG().s]
    );
    assert(initialize_account().is_valid_signature(message_hash, signatures) == VALIDATED, 'invalid signature');
}

#[test]
fn valid_with_guardian_backup() {
    let owner_pub_key = OWNER_KEY();
    let guardian_backup_pubkey = GUARDIAN_BACKUP_KEY();
    let account = initialize_account_with(OWNER_KEY(), 1);
    let guardian_backup = Option::Some(starknet_signer_from_pubkey(guardian_backup_pubkey));
    account.change_guardian_backup(guardian_backup);
    let signatures = to_starknet_signer_signatures(
        array![
            owner_pub_key,
            OWNER_SIG().r,
            OWNER_SIG().s,
            guardian_backup_pubkey,
            GUARDIAN_BACKUP_SIG().r,
            GUARDIAN_BACKUP_SIG().s
        ]
    );
    assert(account.is_valid_signature(message_hash, signatures) == VALIDATED, 'invalid signature');
}

#[test]
fn invalid_hash_1() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(array![OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s]);
    assert(account.is_valid_signature(0, signatures) == 0, 'invalid signature');
}

#[test]
fn invalid_hash_2() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(array![OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s]);
    assert(account.is_valid_signature(123, signatures) == 0, 'invalid signature');
}

#[test]
fn invalid_owner_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(array![1, 2, 3]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature');
    let signatures = to_starknet_signer_signatures(array![WRONG_OWNER_KEY(), WRONG_OWNER_SIG().r, WRONG_OWNER_SIG().s]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature');
    let signatures = to_starknet_signer_signatures(
        array![GUARDIAN_KEY(), GUARDIAN_BACKUP_SIG().r, GUARDIAN_BACKUP_SIG().s]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature');
}

#[test]
fn invalid_owner_with_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(
        array![1, 2, 3, GUARDIAN_BACKUP_KEY(), GUARDIAN_BACKUP_SIG().r, GUARDIAN_BACKUP_SIG().s]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature');
    let signatures = to_starknet_signer_signatures(
        array![
            WRONG_OWNER_KEY(),
            WRONG_OWNER_SIG().r,
            WRONG_OWNER_SIG().s,
            GUARDIAN_BACKUP_KEY(),
            GUARDIAN_BACKUP_SIG().r,
            GUARDIAN_BACKUP_SIG().s
        ]
    );
    account.is_valid_signature(message_hash, signatures);
}

#[test]
fn valid_owner_with_invalid_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s, 1, 2, 3]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 1');
    let signatures = to_starknet_signer_signatures(array![OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s, 25, 42, 69]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 2');
    let signatures = to_starknet_signer_signatures(
        array![
            OWNER_KEY(),
            OWNER_SIG().r,
            OWNER_SIG().s,
            WRONG_GUARDIAN_KEY(),
            WRONG_GUARDIAN_SIG().r,
            WRONG_GUARDIAN_SIG().s
        ]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 3');
    let signatures = to_starknet_signer_signatures(
        array![OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s, OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 4');
}

#[test]
fn invalid_owner_with_invalid_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![1, 2, 3, 4, 5, 6]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 1');
    let signatures = to_starknet_signer_signatures(array![2, 42, 99, 6, 534, 123]);
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 2');
    let signatures = to_starknet_signer_signatures(
        array![WRONG_OWNER_KEY(), WRONG_OWNER_SIG().r, WRONG_OWNER_SIG().s, 1, 2, 3]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 3');
    let signatures = to_starknet_signer_signatures(
        array![1, 2, 3, WRONG_GUARDIAN_KEY(), WRONG_GUARDIAN_SIG().r, WRONG_GUARDIAN_SIG().s]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 4');
    let signatures = to_starknet_signer_signatures(
        array![
            WRONG_OWNER_KEY(),
            WRONG_OWNER_SIG().r,
            WRONG_OWNER_SIG().s,
            WRONG_GUARDIAN_KEY(),
            WRONG_GUARDIAN_SIG().r,
            WRONG_GUARDIAN_SIG().s
        ]
    );
    assert(account.is_valid_signature(message_hash, signatures) == 0, 'invalid signature 5');
}

#[test]
#[should_panic(expected: ('argent/undeserializable',))]
fn invalid_empty_signature_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = array![];
    account.is_valid_signature(message_hash, signatures);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-length',))]
fn invalid_signature_length_without_guardian() {
    let account = initialize_account_without_guardian();
    let signatures = to_starknet_signer_signatures(
        array![
            OWNER_KEY(),
            OWNER_SIG().r,
            OWNER_SIG().s,
            GUARDIAN_BACKUP_KEY(),
            GUARDIAN_BACKUP_SIG().r,
            GUARDIAN_BACKUP_SIG().s
        ]
    );
    account.is_valid_signature(message_hash, signatures);
}

#[test]
#[should_panic(expected: ('argent/undeserializable',))]
fn invalid_empty_signature_with_guardian() {
    let account = initialize_account();
    let signatures = array![];
    account.is_valid_signature(message_hash, signatures);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-length',))]
fn invalid_signature_length_with_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![OWNER_KEY(), OWNER_SIG().r, OWNER_SIG().s]);
    account.is_valid_signature(message_hash, signatures);
}
