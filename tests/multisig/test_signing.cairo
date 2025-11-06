use argent::signer::signer_signature::{SignerSignature, SignerSignatureTrait, SignerTrait};
use argent::utils::serialization::serialize;
use crate::{
    ITestArgentMultisigDispatcherTrait, MultisigSetup, SignerKeyPairImpl, StarknetKeyPair, initialize_multisig_m_of_n,
};
use snforge_std::{generate_random_felt};
use starknet::VALIDATED;

#[test]
fn test_signature() {
    let threshold = 1;
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(threshold, 1);

    let tx_hash = generate_random_felt();
    let signature = serialize(@array![signers[0].sign(tx_hash)]);
    assert_eq!(multisig.is_valid_signature(tx_hash, signature), VALIDATED);
}

#[test]
fn test_double_signature() {
    // init
    let threshold = 2;
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(threshold, 2);

    let tx_hash = generate_random_felt();
    let sig_1 = signers[0].sign(tx_hash);
    let sig_2 = signers[1].sign(tx_hash);
    let signature = serialize(@sort_signers_by_guid(@sig_1, @sig_2));
    assert_eq!(multisig.is_valid_signature(tx_hash, signature), VALIDATED);
}

#[test]
#[should_panic(expected: ('argent/signatures-not-sorted',))]
fn test_double_signature_order() {
    let threshold = 2;
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(threshold, 2);

    let tx_hash = generate_random_felt();
    let sig_1 = signers[0].sign(tx_hash);
    let sig_2 = signers[1].sign(tx_hash);
    let sorted_signatures = sort_signers_by_guid(@sig_1, @sig_2);
    // Invert the order of the signers
    let signature = serialize(@array![*sorted_signatures[1], *sorted_signatures[0]]);
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/signatures-not-sorted',))]
fn test_same_owner_twice() {
    let threshold = 2;
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(threshold, 2);

    let tx_hash = generate_random_felt();
    let sig_1 = signers[0].sign(tx_hash);
    let signature = serialize(@array![sig_1, sig_1]);
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/signature-invalid-length',))]
fn test_missing_owner_signature() {
    let threshold = 2;
    let MultisigSetup { multisig, signers, .. } = initialize_multisig_m_of_n(threshold, 2);

    let tx_hash = generate_random_felt();
    let sig_1 = signers[0].sign(tx_hash);
    let signature = serialize(@array![sig_1]);
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn test_short_signature() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);
    // Missing S
    let tx_hash = generate_random_felt();
    let pubkey = 42;
    let r = 1;
    let signature = array![1, pubkey, r];
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/not-a-signer',))]
fn test_not_a_signer() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);

    let tx_hash = generate_random_felt();
    let signature = serialize(@array![StarknetKeyPair::random().sign(tx_hash)]);
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/signature-invalid-length',))]
fn test_long_signature() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);
    let tx_hash = generate_random_felt();
    let sig_1 = StarknetKeyPair::random().sign(tx_hash);
    let sig_2 = StarknetKeyPair::random().sign(tx_hash);
    let signature = serialize(@array![sig_1, sig_2]);
    multisig.is_valid_signature(tx_hash, signature);
}

#[test]
#[should_panic(expected: ('argent/invalid-signature-format',))]
fn test_empty_array_signature() {
    let MultisigSetup { multisig, .. } = initialize_multisig_m_of_n(1, 1);

    let tx_hash = generate_random_felt();
    multisig.is_valid_signature(tx_hash, array![]);
}

// Utility function to sort signers by guid
fn sort_signers_by_guid(
    signer_signature_1: @SignerSignature, signer_signature_2: @SignerSignature,
) -> Array<SignerSignature> {
    let signer_1_guid: u256 = (*signer_signature_1).signer().into_guid().into();
    let signer_2_guid: u256 = (*signer_signature_2).signer().into_guid().into();
    if signer_1_guid < signer_2_guid {
        array![*signer_signature_1, *signer_signature_2]
    } else {
        array![*signer_signature_2, *signer_signature_1]
    }
}
