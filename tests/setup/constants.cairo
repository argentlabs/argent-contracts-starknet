use argent::signer::signer_signature::{Signer, StarknetSignature, starknet_signer_from_pubkey};
use snforge_std::signature::{KeyPairTrait, stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl}};

#[derive(Drop, Serde, Copy)]
pub struct KeyAndSig {
    pub pubkey: felt252,
    pub sig: StarknetSignature,
}

pub const ARGENT_ACCOUNT_ADDRESS: felt252 = 0x222222222;

pub const TX_HASH: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

pub fn OWNER() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('OWNER');
    let (r, s): (felt252, felt252) = new_owner.sign(TX_HASH).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

pub fn MULTISIG_OWNER(key: felt252) -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key(key);
    let (r, s): (felt252, felt252) = new_owner.sign(TX_HASH).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

pub fn GUARDIAN() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('GUARDIAN');
    let (r, s): (felt252, felt252) = new_owner.sign(TX_HASH).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

pub fn WRONG_OWNER() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('WRONG_OWNER');
    let (r, s): (felt252, felt252) = new_owner.sign(TX_HASH).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

pub fn WRONG_GUARDIAN() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('WRONG_GUARDIAN');
    let (r, s): (felt252, felt252) = new_owner.sign(TX_HASH).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}

pub fn SIGNER_1() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(1).pubkey)
}

pub fn SIGNER_2() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(2).pubkey)
}

pub fn SIGNER_3() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(3).pubkey)
}

pub fn SIGNER_4() -> Signer {
    starknet_signer_from_pubkey(MULTISIG_OWNER(4).pubkey)
}
