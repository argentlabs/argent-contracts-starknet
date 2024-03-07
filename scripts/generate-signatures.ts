import { num } from "starknet";
import { StarknetKeyPair, signChangeOwnerMessage } from "../tests-integration/lib";
import { Signature, Wallet, id } from "ethers";

const owner = new StarknetKeyPair(1n);
const guardian = new StarknetKeyPair(2n);
const guardian_backup = new StarknetKeyPair(3n);

const new_owner = new StarknetKeyPair(4n);

const wrong_owner = new StarknetKeyPair(7n);
const wrong_guardian = new StarknetKeyPair(8n);

async function calculate_account_signature() {
  const hash = "0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8";
  const invalid_hash = "0x02d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a561fa7";

  const [owner_r, owner_s] = await owner.signRaw(hash);
  const [guardian_r, guardian_s] = await guardian.signRaw(hash);
  const [guardian_backup_r, guardian_backup_s] = await guardian_backup.signRaw(hash);
  const [wrong_owner_r, wrong_owner_s] = await wrong_owner.signRaw(hash);
  const [wrong_guardian_r, wrong_guardian_s] = await wrong_guardian.signRaw(hash);

  console.log(`
    const message_hash: felt252 = ${num.toHex(hash)};
    const invalid_hash: felt252 = ${num.toHex(invalid_hash)};

    const owner_pubkey: felt252 = ${num.toHex(owner.publicKey)};
    const owner_r: felt252 = ${num.toHex(owner_r)};
    const owner_s: felt252 = ${num.toHex(owner_s)};

    const guardian_pubkey: felt252 = ${num.toHex(guardian.publicKey)};
    const guardian_r: felt252 = ${num.toHex(guardian_r)};
    const guardian_s: felt252 = ${num.toHex(guardian_s)};

    const guardian_backup_pubkey: felt252 = ${num.toHex(guardian_backup.publicKey)};
    const guardian_backup_r: felt252 = ${num.toHex(guardian_backup_r)};
    const guardian_backup_s: felt252 = ${num.toHex(guardian_backup_s)};

    const wrong_owner_pubkey: felt252 = ${num.toHex(wrong_owner.publicKey)};
    const wrong_owner_r: felt252 = ${num.toHex(wrong_owner_r)};
    const wrong_owner_s: felt252 = ${num.toHex(wrong_owner_s)};

    const wrong_guardian_pubkey: felt252 = ${num.toHex(wrong_guardian.publicKey)};
    const wrong_guardian_r: felt252 = ${num.toHex(wrong_guardian_r)};
    const wrong_guardian_s: felt252 = ${num.toHex(wrong_guardian_s)};
`);
}

async function calculate_account_signature_with_eth() {
  // Ethers requires hash to be pair length
  const hash = "0x02d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8";
  const ethSigner = new Wallet(id("9n"));
  const [owner_r, owner_s] = await owner.signRaw(hash);
  const signature = Signature.from(ethSigner.signingKey.sign(hash));

  console.log(`
    const message_hash: felt252 = ${num.toHex(hash)};

    const owner_pubkey: felt252 = ${num.toHex(owner.publicKey)};
    const owner_r: felt252 = ${num.toHex(owner_r)};
    const owner_s: felt252 = ${num.toHex(owner_s)};

    const owner_pubkey_eth: felt252 = ${ethSigner.address};
    const owner_eth_r: u256 = ${signature.r};
    const owner_eth_s: u256 = ${signature.s};
    const owner_eth_v: felt252 = ${signature.v};
`);
}

async function calculate_change_owner_signature() {
  // message_hash = pedersen(0, (change_owner selector, chainid, contract address, old_owner))
  const chain_id = "0";
  const contract_address = "0x161ECB417F1E71ACC57AB04B9125EC43584469F09E501803A4707A8F3E6C1EC";
  const old_owner = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfcan;

  const starknetSignature = await signChangeOwnerMessage(contract_address, old_owner, new_owner, chain_id);

  console.log(`
    const new_owner_pubkey: felt252 = ${num.toHex(new_owner.publicKey)};
    const new_owner_r: felt252 = ${num.toHex(starknetSignature[2])};
    const new_owner_s: felt252 = ${num.toHex(starknetSignature[3])};
    `);
}

calculate_account_signature();
calculate_account_signature_with_eth();
calculate_change_owner_signature();
