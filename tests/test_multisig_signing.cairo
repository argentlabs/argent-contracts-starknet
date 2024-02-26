use argent::signer::signer_signature::{Signer, StarknetSigner, SignerSignature};
use argent_tests::setup::{
    multisig_test_setup::{
        initialize_multisig_with, signer_pubkey_1, signer_pubkey_2, signer_pubkey_3, ITestArgentMultisigDispatcherTrait,
        initialize_multisig_with_one_signer
    },
    utils::to_starknet_signer_signatures
};
use starknet::VALIDATED;

const message_hash: felt252 = 424242;

const signer_1_signature_r: felt252 = 780418022109335103732757207432889561210689172704851180349474175235986529895;
const signer_1_signature_s: felt252 = 117732574052293722698213953663617651411051623743664517986289794046851647347;

const signer_2_signature_r: felt252 = 2543572729543774155040746789716602521360190010191061121815852574984983703153;
const signer_2_signature_s: felt252 = 3047778680024311010844701802416003052323696285920266547201663937333620527443;

#[test]
fn test_signature() {
    let multisig = initialize_multisig_with_one_signer();

    let signature = to_starknet_signer_signatures(array![signer_pubkey_1, signer_1_signature_r, signer_1_signature_s]);
    assert(multisig.is_valid_signature(message_hash, signature) == VALIDATED, 'bad signature');
}
#[test]
fn test_double_signature() {
    // init
    let threshold = 2;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let multisig = initialize_multisig_with(threshold, array![signer_1, signer_2].span());

    let signature = to_starknet_signer_signatures(
        array![
            signer_pubkey_1,
            signer_1_signature_r,
            signer_1_signature_s,
            signer_pubkey_2,
            signer_2_signature_r,
            signer_2_signature_s
        ]
    );
    assert(multisig.is_valid_signature(message_hash, signature) == VALIDATED, 'bad signature');
}

#[test]
#[should_panic(expected: ('argent/signatures-not-sorted', 'ENTRYPOINT_FAILED'))]
fn test_double_signature_order() {
    let threshold = 2;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let multisig = initialize_multisig_with(threshold, array![signer_1, signer_2].span());

    let signature = to_starknet_signer_signatures(
        array![
            signer_pubkey_2,
            signer_2_signature_r,
            signer_2_signature_s,
            signer_pubkey_1,
            signer_1_signature_r,
            signer_1_signature_s
        ]
    );
    multisig.is_valid_signature(message_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/signatures-not-sorted', 'ENTRYPOINT_FAILED'))]
fn test_same_owner_twice() {
    let threshold = 2;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let multisig = initialize_multisig_with(threshold, array![signer_1, signer_2].span());

    let signature = to_starknet_signer_signatures(
        array![
            signer_pubkey_1,
            signer_1_signature_r,
            signer_1_signature_s,
            signer_pubkey_1,
            signer_1_signature_r,
            signer_1_signature_s
        ]
    );
    multisig.is_valid_signature(message_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/signature-invalid-length', 'ENTRYPOINT_FAILED'))]
fn test_missing_owner_signature() {
    let threshold = 2;
    let signer_1 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_1 });
    let signer_2 = Signer::Starknet(StarknetSigner { pubkey: signer_pubkey_2 });
    let multisig = initialize_multisig_with(threshold, array![signer_1, signer_2].span());

    let signature = to_starknet_signer_signatures(array![signer_pubkey_1, signer_1_signature_r, signer_1_signature_s]);
    multisig.is_valid_signature(message_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/undeserializable', 'ENTRYPOINT_FAILED'))]
fn test_short_signature() {
    let multisig = initialize_multisig_with_one_signer();

    let mut signature = array![1];
    signer_pubkey_1.serialize(ref signature);
    multisig.is_valid_signature(message_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/signature-invalid-length', 'ENTRYPOINT_FAILED'))]
fn test_long_signature() {
    let multisig = initialize_multisig_with_one_signer();

    let signature = to_starknet_signer_signatures(
        array![
            signer_pubkey_1,
            signer_1_signature_r,
            signer_1_signature_s,
            signer_pubkey_2,
            signer_2_signature_r,
            signer_2_signature_s
        ]
    );
    multisig.is_valid_signature(message_hash, signature);
}
