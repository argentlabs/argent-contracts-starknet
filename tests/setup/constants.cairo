use argent::signer::signer_signature::{Secp256k1Signature, StarknetSignature};
use ecdsa::check_ecdsa_signature;
use hash::{HashStateTrait};
use pedersen::{PedersenTrait};
use snforge_std::signature::{
    SignerTrait, KeyPair, KeyPairTrait,
    stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl, StarkCurveVerifierImpl},
    secp256k1_curve::{Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl, Secp256k1CurveVerifierImpl,}
};

use starknet::secp256k1::{Secp256k1Point};


const ARGENT_ACCOUNT_ADDRESS: felt252 = 0x222222222;

const tx_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;
const tx_hash_u256: u256 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;


fn new_owner_message_hash(old_signer: felt252) -> felt252 {
    PedersenTrait::new(0)
        .update(selector!("change_owner"))
        .update('SN_GOERLI')
        .update(ARGENT_ACCOUNT_ADDRESS)
        .update(OWNER_KEY())
        .update(4)
        .finalize()
}

fn ETH_ADDRESS() -> Secp256k1Point {
    KeyPairTrait::<u256, Secp256k1Point>::from_secret_key('ETH').public_key
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

fn MULTISIG_OWNER_SIG(owner: felt252) -> StarknetSignature {
    let owner = KeyPairTrait::from_secret_key(owner);
    let (r, s): (felt252, felt252) = owner.sign(tx_hash);
    StarknetSignature { r, s }
}

fn OWNER_SIG() -> StarknetSignature {
    let owner = KeyPairTrait::from_secret_key('OWNER');
    let (r, s): (felt252, felt252) = owner.sign(tx_hash);
    StarknetSignature { r, s }
}

fn GUARDIAN_SIG() -> StarknetSignature {
    let guardian = KeyPairTrait::from_secret_key('GUARDIAN');
    let (r, s): (felt252, felt252) = guardian.sign(tx_hash);
    StarknetSignature { r, s }
}

fn GUARDIAN_BACKUP_SIG() -> StarknetSignature {
    let guardian_backup = KeyPairTrait::from_secret_key('GUARDIAN_BACKUP');
    let (r, s): (felt252, felt252) = guardian_backup.sign(tx_hash);
    StarknetSignature { r, s }
}


fn WRONG_OWNER_SIG() -> StarknetSignature {
    let wrong_owner = KeyPairTrait::from_secret_key('WRONG_OWNER');
    let (r, s): (felt252, felt252) = wrong_owner.sign(tx_hash);
    StarknetSignature { r, s }
}

fn WRONG_GUARDIAN_SIG() -> StarknetSignature {
    let wrong_guardian = KeyPairTrait::from_secret_key('WRONG_GUARDIAN');
    let (r, s): (felt252, felt252) = wrong_guardian.sign(tx_hash);
    StarknetSignature { r, s }
}

fn ETH_SIGNER_SIG() -> Secp256k1Signature {
    let eth_signer = KeyPairTrait::<u256, Secp256k1Point>::from_secret_key('ETH');
    let (r, s): (u256, u256) = eth_signer.sign(tx_hash_u256);
    Secp256k1Signature { r, s, y_parity: false }
}

// change owner 
fn NEW_OWNER_SIG() -> StarknetSignature {
    let new_owner = KeyPairTrait::from_secret_key('NEW_OWNER');
    let new_owner_message_hash = new_owner_message_hash(new_owner.public_key);
    let (r, s): (felt252, felt252) = new_owner.sign(new_owner_message_hash);
    StarknetSignature { r, s }
}
