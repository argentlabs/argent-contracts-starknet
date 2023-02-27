use array::ArrayTrait;
use contracts::ArgentMultisigAccount;
use debug::print_felt;
use traits::Into;

const message_hash: felt = 424242;
const signer_pubkey_2: felt = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_2_signature_r: felt =
    780418022109335103732757207432889561210689172704851180349474175235986529895;
const signer_2_signature_s: felt =
    117732574052293722698213953663617651411051623743664517986289794046851647347;


#[test]
#[available_gas(20000000)]
fn test_signature() {
    // init
    let threshold = 1_u32;
    let mut signers_array = ArrayTrait::new();
    signers_array.append(signer_pubkey_2);
    ArgentMultisigAccount::initialize(threshold, signers_array);

    let mut signature = ArrayTrait::<felt>::new();
    signature.append(signer_pubkey_2);
    signature.append(signer_2_signature_r);
    signature.append(signer_2_signature_s);
    assert(
        ArgentMultisigAccount::is_valid_signature(message_hash, signature) == true, 'bad signature'
    );
}
