import * as utils from "@noble/curves/abstract/utils";
import { p256 as secp256r1 } from "@noble/curves/p256";
import { Signature, Wallet, id } from "ethers";
import { num } from "starknet";
import { StarknetKeyPair } from "../lib";

const hash = "0x02d6479c0758efbb5aa07d35ed5454d728637fceab7ba544d3ea95403a5630a8";

async function calculate_account_signature_with_eth() {
  // Ethers requires hash to be pair length
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
async function calculate_r1_signature() {
  const privateKey = 1n;

  const signature = secp256r1.sign(hash.substring(2), privateKey);

  const publicKeyArray = secp256r1.getPublicKey(privateKey).slice(1);
  console.log(`
    calculate_r1_signature:
    const message_hash: felt252 = ${num.toHex(hash)};
    const pubkey: u256 = ${"0x" + utils.bytesToHex(publicKeyArray)};
    const sig_r: u256 = ${num.toHex(signature.r)};
    const sig_s: u256 = ${num.toHex(signature.s)};
    const sig_y_parity: bool = ${signature.recovery !== 0};

`);
}

await calculate_account_signature_with_eth();
await calculate_r1_signature();
