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

const message_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

fn new_owner_message_hash(old_signer: felt252) -> felt252 {
    PedersenTrait::new(0)
        .update(selector!("change_owner"))
        .update(1536727068981429685321)
        .update(100)
        .update(OWNER_KEY())
        .update(4)
        .finalize()
}

fn MULTISIG_OWNER(key: felt252) -> felt252 {
    KeyPairTrait::from_secret_key(key).public_key
}

fn OWNER_KEY() -> felt252 {
    KeyPairTrait::from_secret_key('OWNER').public_key
}

fn GUARDIAN_KEY() -> felt252 {
    KeyPairTrait::from_secret_key('GUARDIAN').public_key
}

fn GUARDIAN_BACKUP_KEY() -> felt252 {
    KeyPairTrait::from_secret_key('GUARDIAN_BACKUP').public_key
}

fn WRONG_OWNER_KEY() -> felt252 {
    KeyPairTrait::from_secret_key('WRONG_OWNER').public_key
}

fn NEW_OWNER_KEY() -> felt252 {
    KeyPairTrait::from_secret_key('NEW_OWNER').public_key
}

fn WRONG_GUARDIAN_KEY() -> felt252 {
    KeyPairTrait::from_secret_key('WRONG_GUARDIAN').public_key
}

fn OWNER_SIG() -> StarkSignature {
    let owner = KeyPairTrait::from_secret_key('OWNER');
    let (r, s): (felt252, felt252) = owner.sign(message_hash);
    StarkSignature { r, s }
}

fn GUARDIAN_SIG() -> StarkSignature {
    let guardian = KeyPairTrait::from_secret_key('GUARDIAN');
    let (r, s): (felt252, felt252) = guardian.sign(message_hash);
    StarkSignature { r, s }
}

fn GUARDIAN_BACKUP_SIG() -> StarkSignature {
    let guardian_backup = KeyPairTrait::from_secret_key('GUARDIAN_BACKUP');
    let (r, s): (felt252, felt252) = guardian_backup.sign(message_hash);
    StarkSignature { r, s }
}


fn WRONG_OWNER_SIG() -> StarkSignature {
    let wrong_owner = KeyPairTrait::from_secret_key('WRONG_OWNER');
    let (r, s): (felt252, felt252) = wrong_owner.sign(message_hash);
    StarkSignature { r, s }
}

fn WRONG_GUARDIAN_SIG() -> StarkSignature {
    let wrong_guardian = KeyPairTrait::from_secret_key('WRONG_GUARDIAN');
    let (r, s): (felt252, felt252) = wrong_guardian.sign(message_hash);
    StarkSignature { r, s }
}


// change owner 
fn NEW_OWNER_SIG() -> StarkSignature {
    let new_owner = KeyPairTrait::from_secret_key('NEW_OWNER');
    let new_owner_message_hash = new_owner_message_hash(new_owner.public_key);
    let (r, s): (felt252, felt252) = new_owner.sign(new_owner_message_hash);
    StarkSignature { r, s }
}
