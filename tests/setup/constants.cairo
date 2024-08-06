use argent::signer::signer_signature::{SignerTrait, StarknetSignature};
use snforge_std::signature::{KeyPairTrait, stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl}};

#[derive(Drop, Serde, Copy)]
struct KeyAndSig {
    pubkey: felt252,
    sig: StarknetSignature,
}

const ARGENT_ACCOUNT_ADDRESS: felt252 = 0x222222222;

const tx_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

fn OWNER() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('OWNER');
    let (r, s): (felt252, felt252) = new_owner.sign(tx_hash).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

fn MULTISIG_OWNER(key: felt252) -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key(key);
    let (r, s): (felt252, felt252) = new_owner.sign(tx_hash).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

fn GUARDIAN() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('GUARDIAN');
    let (r, s): (felt252, felt252) = new_owner.sign(tx_hash).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

fn GUARDIAN_BACKUP() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('GUARDIAN_BACKUP');
    let (r, s): (felt252, felt252) = new_owner.sign(tx_hash).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

fn WRONG_OWNER() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('WRONG_OWNER');
    let (r, s): (felt252, felt252) = new_owner.sign(tx_hash).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

fn WRONG_GUARDIAN() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('WRONG_GUARDIAN');
    let (r, s): (felt252, felt252) = new_owner.sign(tx_hash).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}
