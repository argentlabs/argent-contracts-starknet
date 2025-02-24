use crate::setup::argent_account_setup::{
    ITestArgentAccountDispatcher, ITestArgentAccountSafeDispatcher, ITestArgentAccountSafeDispatcherTrait,
};
use crate::{
    Felt252TryIntoStarknetSigner, GUARDIAN, ITestArgentAccountDispatcherTrait, OWNER, TX_HASH, WRONG_GUARDIAN,
    WRONG_OWNER, initialize_account, initialize_account_without_guardian, to_starknet_signatures,
    to_starknet_signer_signatures,
};
use starknet::VALIDATED;

#[generate_trait]
impl SignatureCheckerTrait of ISignatureCheckerTrait {
    fn check_signature(self: @ITestArgentAccountDispatcher, hash: felt252, signature: Array<felt252>) -> bool {
        let safe_dispatcher = ITestArgentAccountSafeDispatcher { contract_address: *self.contract_address };
        match safe_dispatcher.is_valid_signature(hash, signature) {
            Result::Ok(validated) => validated == VALIDATED,
            Result::Err(_) => false,
        }
    }
}

#[test]
fn valid_no_guardian() {
    let account = initialize_account_without_guardian();
    assert!(account.check_signature(TX_HASH, to_starknet_signatures(array![OWNER()])));
}

#[test]
fn valid_with_guardian() {
    assert!(initialize_account().check_signature(TX_HASH, to_starknet_signatures(array![OWNER(), GUARDIAN()])));
}

#[test]
fn invalid_hash() {
    let account = initialize_account_without_guardian();
    assert!(!account.check_signature(0, to_starknet_signatures(array![OWNER()])));
}

#[test]
fn invalid_owner_without_guardian() {
    let account = initialize_account_without_guardian();
    assert!(!account.check_signature(TX_HASH, to_starknet_signer_signatures(array![1, 2, 3])));
    assert!(!account.check_signature(TX_HASH, to_starknet_signatures(array![WRONG_OWNER()])));
}

#[test]
fn invalid_owner_with_guardian() {
    let account = initialize_account();
    assert!(!account.check_signature(TX_HASH, to_starknet_signer_signatures(array![1, 2, 3, 5, 8, 8])));
    assert!(!account.check_signature(TX_HASH, to_starknet_signatures(array![WRONG_OWNER(), GUARDIAN()])));
}

#[test]
fn valid_owner_with_invalid_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![OWNER().pubkey, OWNER().sig.r, OWNER().sig.s, 1, 2, 3]);
    assert!(!account.check_signature(TX_HASH, signatures));
    let signatures = to_starknet_signatures(array![OWNER(), WRONG_GUARDIAN()]);
    assert!(!account.check_signature(TX_HASH, signatures));
    let signatures = to_starknet_signatures(array![OWNER(), OWNER()]);
    assert!(!account.check_signature(TX_HASH, signatures));
}

#[test]
fn invalid_owner_with_invalid_guardian() {
    let account = initialize_account();
    let signatures = to_starknet_signer_signatures(array![1, 2, 3, 4, 5, 6]);
    assert!(!account.check_signature(TX_HASH, signatures));
    let signatures = to_starknet_signatures(array![WRONG_OWNER(), WRONG_GUARDIAN()]);
    assert!(!account.check_signature(TX_HASH, signatures));
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn invalid_empty_signature_without_guardian() {
    initialize_account_without_guardian().is_valid_signature(TX_HASH, array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-guardian-sig',))]
fn invalid_signature_length_without_guardian() {
    let account = initialize_account_without_guardian();
    account.is_valid_signature(TX_HASH, to_starknet_signatures(array![OWNER(), GUARDIAN()]));
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn invalid_empty_signature_with_guardian() {
    initialize_account().is_valid_signature(TX_HASH, array![]);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-length',))]
fn invalid_empty_span_signature() {
    initialize_account().is_valid_signature(TX_HASH, array![0]);
}

#[test]
#[should_panic(expected: ('argent/missing-guardian-sig',))]
fn invalid_signature_length_with_guardian() {
    initialize_account().is_valid_signature(TX_HASH, to_starknet_signatures(array![OWNER()]));
}

