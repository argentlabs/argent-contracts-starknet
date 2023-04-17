use array::ArrayTrait;
use traits::Into;

use multisig::ArgentMultisigAccount;

const message_hash: felt252 = 424242;
const signer_pubkey_2: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_2_signature_r: felt252 =
    780418022109335103732757207432889561210689172704851180349474175235986529895;
const signer_2_signature_s: felt252 =
    117732574052293722698213953663617651411051623743664517986289794046851647347;

#[test]
#[available_gas(20000000)]
fn test_signature() {
    // init
    let threshold = 1;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_2);
    ArgentMultisigAccount::constructor(threshold, signers_array);

    let mut signature = ArrayTrait::<felt252>::new();
    signature.append(signer_pubkey_2);
    signature.append(signer_2_signature_r);
    signature.append(signer_2_signature_s);
    let valid_signature = ArgentMultisigAccount::is_valid_signature(message_hash, signature);
    assert(valid_signature, 'bad signature');
}
