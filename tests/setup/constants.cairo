use ecdsa::check_ecdsa_signature;
use hash::{HashStateTrait};
use pedersen::{PedersenTrait};
use snforge_std::signature::{
    SignerTrait, KeyPair, KeyPairTrait,
    stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl, StarkCurveVerifierImpl}
};
#[derive(Clone, Copy, Drop)]
struct StarkSignature {
    r: felt252,
    s: felt252
}

fn new_owner_message_hash(old_signer: felt252) -> felt252 {
    PedersenTrait::new(0)
        .update(selector!("change_owner"))
        .update(1536727068981429685321)
        .update(100)
        .update(OWNER_KEY())
        .update(4)
        .finalize()
}

fn OWNER_KEY() -> felt252 {
    KeyPairTrait::from_secret_key(1).public_key
}

fn GUARDIAN_KEY() -> felt252 {
    KeyPairTrait::from_secret_key(2).public_key
}

fn WRONG_OWNER_KEY() -> felt252 {
    KeyPairTrait::from_secret_key(3).public_key
}

fn NEW_OWNER_KEY() -> felt252 {
    KeyPairTrait::from_secret_key(4).public_key
}

fn NEW_OWNER_SIG() -> StarkSignature {
    let new_owner = KeyPairTrait::from_secret_key(4);

    let message_hash = new_owner_message_hash(new_owner.public_key);
    let (r, s): (felt252, felt252) = new_owner.sign(message_hash);

    StarkSignature { r, s }
}

fn WRONG_OWNER_SIG() -> StarkSignature {
    let wrong_owner = KeyPairTrait::from_secret_key(3);
    let message_hash = new_owner_message_hash(wrong_owner.public_key);
    let (r, s): (felt252, felt252) = wrong_owner.sign(message_hash);
    StarkSignature { r, s }
}
