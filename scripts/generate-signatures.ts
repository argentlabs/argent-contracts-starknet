import * as utils from "@noble/curves/abstract/utils";
import { p256 as secp256r1 } from "@noble/curves/p256";
import { Signature, Wallet, id } from "ethers";
import { num } from "starknet";
import { StarknetKeyPair } from "../lib";

async function calculate_account_signature_with_eth() {
  // Ethers requires hash to be pair length
  const hash = "0x02d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8";

  const owner = new StarknetKeyPair(1n);
  const ethSigner = new Wallet(id("9n"));
  const [owner_r, owner_s] = await owner.signRaw(hash);
  const signature = Signature.from(ethSigner.signingKey.sign(hash));

  console.log(`
    calculate_account_signature_with_eth:
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

const r1PrivateKey = 1n;

async function calculate_r1_signature(hash: string, expectedLowS: boolean, expectedYParity: boolean) {
  // const hash = "0x02d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8";

  // const randomBytes = "0x"+ [...Array(256/8)].map(() => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('');
  // const hash = randomBytes;

  const signature = secp256r1.sign(hash.substring(2), r1PrivateKey);
  let yParity = signature.recovery !== 0;
  const lowS = signature.s <= secp256r1.CURVE.n / 2n;
  if (expectedLowS !== lowS) {
    throw new Error(`Hash didn't produce a lowS=${lowS} signature`);
  }

  let s = signature.s;
  if (!lowS) {
    s = secp256r1.CURVE.n - s;
    yParity = !yParity;
  }

  if (expectedYParity !== yParity) {
    throw new Error(`Hash didn't produce a yParity=${expectedYParity} signature`);
  }

  const suffix = (lowS ? "low" : "high") + "_" + (yParity ? "even" : "odd");

  console.log(`
    const message_hash_${suffix}: felt252 = ${num.toHex(hash)};
    const sig_r_${suffix}: u256 = ${num.toHex(signature.r)};
    const sig_s_${suffix}: u256 = ${num.toHex(s)};
`);

  // console.log(`lowS: ${lowS}, yParity: ${yParity}, hash: ${hash}`);
}

await calculate_account_signature_with_eth();
console.log(`
    calculate_r1_signature:
    const pubkey: u256 = ${"0x" + utils.bytesToHex(secp256r1.getPublicKey(r1PrivateKey).slice(1))};
`);
await calculate_r1_signature("0x0100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403000000a", true, true);
await calculate_r1_signature("0x0100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403000000f", true, false);
await calculate_r1_signature("0x0100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000000", false, true);
await calculate_r1_signature("0x0100009c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea954030000001", false, false);
