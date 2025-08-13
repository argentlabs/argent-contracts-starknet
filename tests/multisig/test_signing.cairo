use crate::{
    ITestArgentMultisigDispatcherTrait, MULTISIG_OWNER, SIGNER_1, SIGNER_2, TX_HASH, initialize_multisig_with,
    initialize_multisig_with_one_signer, to_starknet_signatures, to_starknet_signer_signatures,
};
use starknet::VALIDATED;

#[test]
fn test_signature() {
    let multisig = initialize_multisig_with_one_signer();

    let signature = to_starknet_signatures(array![MULTISIG_OWNER(1)]);
    assert_eq!(multisig.is_valid_signature(TX_HASH, signature), VALIDATED);
}

#[test]
fn test_double_signature() {
    // init
    let threshold = 2;
    let multisig = initialize_multisig_with(threshold, array![SIGNER_1(), SIGNER_2()].span());

    let signature = to_starknet_signatures(array![MULTISIG_OWNER(2), MULTISIG_OWNER(1)]);
    assert_eq!(multisig.is_valid_signature(TX_HASH, signature), VALIDATED);
}

#[test]
#[should_panic(expected: ('argent/signatures-not-sorted',))]
fn test_double_signature_order() {
    let threshold = 2;
    let multisig = initialize_multisig_with(threshold, array![SIGNER_1(), SIGNER_2()].span());

    let signature = to_starknet_signatures(array![MULTISIG_OWNER(1), MULTISIG_OWNER(2)]);
    multisig.is_valid_signature(TX_HASH, signature);
}

#[test]
#[should_panic(expected: ('argent/signatures-not-sorted',))]
fn test_same_owner_twice() {
    let threshold = 2;
    let multisig = initialize_multisig_with(threshold, array![SIGNER_1(), SIGNER_2()].span());

    let signature = to_starknet_signatures(array![MULTISIG_OWNER(1), MULTISIG_OWNER(1)]);
    multisig.is_valid_signature(TX_HASH, signature);
}

#[test]
#[should_panic(expected: ('argent/signature-invalid-length',))]
fn test_missing_owner_signature() {
    let threshold = 2;
    let multisig = initialize_multisig_with(threshold, array![SIGNER_1(), SIGNER_2()].span());

    let signature = to_starknet_signatures(array![MULTISIG_OWNER(1)]);
    multisig.is_valid_signature(TX_HASH, signature);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn test_short_signature() {
    let multisig = initialize_multisig_with_one_signer();

    // Missing S
    let signature = array![1, MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(1).sig.r];
    multisig.is_valid_signature(TX_HASH, signature);
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_not_a_signer() {
    let multisig = initialize_multisig_with_one_signer();

    let signature = to_starknet_signatures(array![MULTISIG_OWNER(2)]);
    multisig.is_valid_signature(TX_HASH, signature);
}

#[test]
#[should_panic(expected: ('argent/signature-invalid-length',))]
fn test_long_signature() {
    let multisig = initialize_multisig_with_one_signer();

    let signature = to_starknet_signer_signatures(
        array![
            MULTISIG_OWNER(1).pubkey,
            MULTISIG_OWNER(1).sig.r,
            MULTISIG_OWNER(2).sig.s,
            MULTISIG_OWNER(2).pubkey,
            MULTISIG_OWNER(2).sig.r,
            MULTISIG_OWNER(2).sig.s,
        ],
    );
    multisig.is_valid_signature(TX_HASH, signature);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn test_empty_array_signature() {
    let multisig = initialize_multisig_with_one_signer();

    multisig.is_valid_signature(TX_HASH, array![]);
}

