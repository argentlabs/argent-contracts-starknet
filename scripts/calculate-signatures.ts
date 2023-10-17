import { hash, shortString } from "starknet";

import { KeyPair } from "../tests/lib/signers";

const owner = new KeyPair("0x1");
const guardian = new KeyPair("0x2");
const guardian_backup = new KeyPair("0x3");

const new_owner = new KeyPair("0x4");
const new_guardian = new KeyPair("0x5");
const new_guardian_backup = new KeyPair("0x6");

const wrong_owner = new KeyPair("0x7");
const wrong_guardian = new KeyPair("0x8");

const ESCAPE_SECURITY_PERIOD = 24 * 7 * 60 * 60;

const VERSION = shortString.encodeShortString("0.2.4");
const NAME = shortString.encodeShortString("ArgentAccount");

const IACCOUNT_ID = 0xa66bd575;
const IACCOUNT_ID_OLD = 0x3943f10f;

const ESCAPE_TYPE_GUARDIAN = 1;
const ESCAPE_TYPE_OWNER = 2;

function calculate_sig_account() {
  const hash = "1283225199545181604979924458180358646374088657288769423115053097913173815464";
  const invalid_hash = "1283225199545181604979924458180358646374088657288769423115053097913173811111";

  const [owner_r, owner_s] = owner.signHash(hash);
  const [guardian_r, guardian_s] = guardian.signHash(hash);
  const [guardian_backup_r, guardian_backup_s] = guardian_backup.signHash(hash);
  const [wrong_owner_r, wrong_owner_s] = wrong_owner.signHash(hash);
  const [wrong_guardian_r, wrong_guardian_s] = wrong_guardian.signHash(hash);

  console.log(`
    const message_hash: felt252 = 0x${BigInt(hash).toString(16)};
    const invalid_hash: felt252 = 0x${BigInt(invalid_hash).toString(16)};

    const owner_pubkey: felt252 = 0x${owner.publicKey};
    const owner_r: felt252 = 0x${owner_r};
    const owner_s: felt252 = 0x${owner_s};

    const guardian_pubkey: felt252 = 0x${guardian.publicKey};
    const guardian_r: felt252 = 0x${guardian_r};
    const guardian_s: felt252 = 0x${guardian_s};

    const guardian_backup_pubkey: felt252 = 0x${guardian_backup.publicKey};
    const guardian_backup_r: felt252 = 0x${guardian_backup_r};
    const guardian_backup_s: felt252 = 0x${guardian_backup_s};

    const wrong_owner_pubkey: felt252 = 0x${wrong_owner.publicKey};
    const wrong_owner_r: felt252 = 0x${wrong_owner_r};
    const wrong_owner_s: felt252 = 0x${wrong_owner_s};

    const wrong_guardian_pubkey: felt252 = 0x${wrong_guardian.publicKey};
    const wrong_guardian_r: felt252 = 0x${wrong_guardian_r};
    const wrong_guardian_s: felt252 = 0x${wrong_guardian_s};
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

    const new_owner_pubkey: felt252 = 0x${new_owner.getPubKey()};
    const new_owner_r: felt252 = 0x${new_owner_r};
    const new_owner_s: felt252 = 0x${new_owner_s};
    `);
}

calculate_sig_change_owner();
