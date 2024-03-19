use argent::signer::signer_signature::{Signer, StarknetSigner, SignerSignature, starknet_signer_from_pubkey};
use starknet::VALIDATED;
use super::setup::constants::{MULTISIG_OWNER, tx_hash};
use super::setup::{
    multisig_test_setup::{
        initialize_multisig_with, ITestArgentMultisigDispatcherTrait, initialize_multisig_with_one_signer
    },
    utils::to_starknet_signer_signatures
};

#[test]
fn test_signature() {
    let multisig = initialize_multisig_with_one_signer();

    let signature = to_starknet_signer_signatures(
        array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(1).sig.r, MULTISIG_OWNER(1).sig.s]
    );
    assert(multisig.is_valid_signature(tx_hash, signature) == VALIDATED, 'bad signature');
}

#[test]
fn test_double_signature() {
    // init
    let threshold = 2;
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let multisig = initialize_multisig_with(threshold, array![signer_1, signer_2].span());

    let signature = to_starknet_signer_signatures(
        array![
            MULTISIG_OWNER(1).pubkey,
            MULTISIG_OWNER(1).sig.r,
            MULTISIG_OWNER(1).sig.s,
            MULTISIG_OWNER(2).pubkey,
            MULTISIG_OWNER(2).sig.r,
            MULTISIG_OWNER(2).sig.s
        ]
    );
    assert(multisig.is_valid_signature(tx_hash, signature) == VALIDATED, 'bad signature');
}

#[test]
#[should_panic(expected: ('argent/signatures-not-sorted',))]
fn test_double_signature_order() {
    let threshold = 2;
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let multisig = initialize_multisig_with(threshold, array![signer_1, signer_2].span());

    let signature = to_starknet_signer_signatures(
        array![
            MULTISIG_OWNER(2).pubkey,
            MULTISIG_OWNER(2).sig.r,
            MULTISIG_OWNER(2).sig.s,
            MULTISIG_OWNER(1).pubkey,
            MULTISIG_OWNER(1).sig.r,
            MULTISIG_OWNER(1).sig.s
        ]
    );
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/signatures-not-sorted',))]
fn test_same_owner_twice() {
    let threshold = 2;
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let multisig = initialize_multisig_with(threshold, array![signer_1, signer_2].span());

    let signature = to_starknet_signer_signatures(
        array![
            MULTISIG_OWNER(1).pubkey,
            MULTISIG_OWNER(1).sig.r,
            MULTISIG_OWNER(1).sig.s,
            MULTISIG_OWNER(1).pubkey,
            MULTISIG_OWNER(1).sig.r,
            MULTISIG_OWNER(1).sig.s
        ]
    );
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/signature-invalid-length',))]
fn test_missing_owner_signature() {
    let threshold = 2;
    let signer_1 = starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey);
    let signer_2 = starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey);
    let multisig = initialize_multisig_with(threshold, array![signer_1, signer_2].span());

    let signature = to_starknet_signer_signatures(
        array![MULTISIG_OWNER(1).pubkey, MULTISIG_OWNER(1).sig.r, MULTISIG_OWNER(2).sig.s]
    );
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/undeserializable',))]
fn test_short_signature() {
    let multisig = initialize_multisig_with_one_signer();

    let mut signature = array![1];
    MULTISIG_OWNER(1).pubkey.serialize(ref signature);
    multisig.is_valid_signature(tx_hash, signature);
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
            MULTISIG_OWNER(2).sig.s
        ]
    );
    multisig.is_valid_signature(tx_hash, signature);
}

