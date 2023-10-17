import { hash, shortString, num } from "starknet";

import { KeyPair } from "../tests/lib/signers";

const owner = new KeyPair(1n);
const guardian = new KeyPair(2n);
const guardian_backup = new KeyPair(3n);

const new_owner = new KeyPair(4n);
const new_guardian = new KeyPair(5n);
const new_guardian_backup = new KeyPair(6n);

const wrong_owner = new KeyPair(7n);
const wrong_guardian = new KeyPair(8n);

const ESCAPE_SECURITY_PERIOD = 24 * 7 * 60 * 60;

const VERSION = shortString.encodeShortString("0.2.4");
const NAME = shortString.encodeShortString("ArgentAccount");

const IACCOUNT_ID = 0xa66bd575;
const IACCOUNT_ID_OLD = 0x3943f10f;

const ESCAPE_TYPE_GUARDIAN = 1;
const ESCAPE_TYPE_OWNER = 2;

function calculate_sig_account() {
  const hash = "0x2d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8";
  const invalid_hash = "0x02d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a561fa7";

  const [owner_r, owner_s] = owner.signHash(hash);
  const [guardian_r, guardian_s] = guardian.signHash(hash);
  const [guardian_backup_r, guardian_backup_s] = guardian_backup.signHash(hash);
  const [wrong_owner_r, wrong_owner_s] = wrong_owner.signHash(hash);
  const [wrong_guardian_r, wrong_guardian_s] = wrong_guardian.signHash(hash);

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

function calculate_sig_change_owner() {
  // message_hash = pedersen(0, (change_owner selector, chainid, contract address, old_owner))
  const change_owner_selector = hash.getSelector("change_owner");
  const chain_id = 0;
  const contract_address = 1n;
  const old_owner = "0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca";

  const message_hash = hash.computeHashOnElements([change_owner_selector, chain_id, contract_address, old_owner]);

  const [new_owner_r, new_owner_s] = new_owner.signHash(message_hash);

  console.log(`

    const new_owner_pubkey: felt252 = ${num.toHex(new_owner.publicKey)};
    const new_owner_r: felt252 = ${num.toHex(new_owner_r)};
    const new_owner_s: felt252 = ${num.toHex(new_owner_s)}; 
    `);
}

calculate_sig_account();
