use argent::signer::signer_signature::{SignerTrait, StarknetSigner, StarknetSignature, starknet_signer_from_pubkey};
use hash::HashStateTrait;
use pedersen::PedersenTrait;
use snforge_std::signature::{KeyPairTrait, stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl}};

#[derive(Drop, Serde, Copy)]
struct KeyAndSig {
    pubkey: felt252,
    sig: StarknetSignature,
}

const ARGENT_ACCOUNT_ADDRESS: felt252 = 0x222222222;

const tx_hash: felt252 = 0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8;

fn new_owner_message_hash(chainId: felt252, account_address: felt252, current_owner_guid: felt252) -> felt252 {
    PedersenTrait::new(0)
        .update(selector!("change_owner"))
        .update(chainId)
        .update(account_address)
        .update(current_owner_guid)
        .update(4)
        .finalize()
}

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

fn NEW_OWNER() -> (StarknetSigner, StarknetSignature) {
    let new_owner_message_hash = new_owner_message_hash(
        'SN_SEPOLIA', ARGENT_ACCOUNT_ADDRESS, starknet_signer_from_pubkey(OWNER().pubkey).into_guid()
    );
    let new_owner = KeyPairTrait::from_secret_key('NEW_OWNER');
    let pubkey = new_owner.public_key.try_into().expect('argent/zero-pubkey');
    let (r, s): (felt252, felt252) = new_owner.sign(new_owner_message_hash).unwrap();
    (StarknetSigner { pubkey }, StarknetSignature { r, s })
}

fn WRONG_GUARDIAN() -> KeyAndSig {
    let new_owner = KeyPairTrait::from_secret_key('WRONG_GUARDIAN');
    let (r, s): (felt252, felt252) = new_owner.sign(tx_hash).unwrap();
    KeyAndSig { pubkey: new_owner.public_key, sig: StarknetSignature { r, s } }
}
