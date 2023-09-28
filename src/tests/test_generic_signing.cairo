use starknet::VALIDATED;

use argent::tests::setup::generic_test_setup::{
    initialize_generic_with, signer_pubkey_1, signer_pubkey_2, signer_pubkey_3,
    ITestArgentGenericAccountDispatcherTrait, initialize_generic_with_one_signer
};
use argent::generic::signer_signature::SignerType;

const message_hash: felt252 = 424242;

const signer_1_signature_r: felt252 =
    780418022109335103732757207432889561210689172704851180349474175235986529895;
const signer_1_signature_s: felt252 =
    117732574052293722698213953663617651411051623743664517986289794046851647347;

const signer_2_signature_r: felt252 =
    2543572729543774155040746789716602521360190010191061121815852574984983703153;
const signer_2_signature_s: felt252 =
    3047778680024311010844701802416003052323696285920266547201663937333620527443;

const signer_type_starknet: felt252 = 0;

#[test]
#[available_gas(20000000)]
fn test_signature() {
    let generic = initialize_generic_with_one_signer();

    let signature = array![
        signer_pubkey_1, signer_type_starknet, 2, signer_1_signature_r, signer_1_signature_s
    ];
    assert(generic.is_valid_signature(message_hash, signature) == VALIDATED, 'bad signature');
}

#[test]
#[available_gas(20000000)]
fn test_double_signature() {
    // init
    let threshold = 2;
    let signers_array = array![signer_pubkey_1, signer_pubkey_2];
    let generic = initialize_generic_with(threshold, signers_array.span());

    let signature = array![
        signer_pubkey_1,
        signer_type_starknet,
        2,
        signer_1_signature_r,
        signer_1_signature_s,
        signer_pubkey_2,
        signer_type_starknet,
        2,
        signer_2_signature_r,
        signer_2_signature_s
    ];
    assert(generic.is_valid_signature(message_hash, signature) == VALIDATED, 'bad signature');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/signatures-not-sorted', 'ENTRYPOINT_FAILED'))]
fn test_double_signature_order() {
    let threshold = 2;
    let signers_array = array![signer_pubkey_2, signer_pubkey_1];
    let generic = initialize_generic_with(threshold, signers_array.span());

    let signature = array![
        signer_pubkey_2,
        signer_type_starknet,
        2,
        signer_2_signature_r,
        signer_2_signature_s,
        signer_pubkey_1,
        signer_type_starknet,
        2,
        signer_1_signature_r,
        signer_1_signature_s
    ];
    generic.is_valid_signature(message_hash, signature);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/signatures-not-sorted', 'ENTRYPOINT_FAILED'))]
fn test_same_owner_twice() {
    let threshold = 2;
    let signers_array = array![signer_pubkey_1, signer_pubkey_2];
    let generic = initialize_generic_with(threshold, signers_array.span());

    let signature = array![
        signer_pubkey_1,
        signer_type_starknet,
        2,
        signer_1_signature_r,
        signer_1_signature_s,
        signer_pubkey_1,
        signer_type_starknet,
        2,
        signer_1_signature_r,
        signer_1_signature_s
    ];
    generic.is_valid_signature(message_hash, signature);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/invalid-signature-length', 'ENTRYPOINT_FAILED'))]
fn test_missing_owner_signature() {
    let threshold = 2;
    let signers_array = array![signer_pubkey_1, signer_pubkey_2];
    let generic = initialize_generic_with(threshold, signers_array.span());

    let signature = array![
        signer_pubkey_1, signer_type_starknet, 2, signer_1_signature_r, signer_1_signature_s
    ];
    generic.is_valid_signature(message_hash, signature);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/invalid-signature-length', 'ENTRYPOINT_FAILED'))]
fn test_short_signature() {
    let generic = initialize_generic_with_one_signer();

    let signature = array![
        signer_pubkey_1,
        signer_type_starknet,
        2,
        signer_1_signature_r,
        signer_1_signature_s,
        signer_pubkey_1,
        signer_type_starknet,
        2,
        signer_1_signature_r
    ];
    generic.is_valid_signature(message_hash, signature);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('argent/invalid-signature-length', 'ENTRYPOINT_FAILED'))]
fn test_long_signature() {
    let generic = initialize_generic_with_one_signer();

    let signature = array![42];
    generic.is_valid_signature(message_hash, signature);
}
