import { Signature, Wallet, id } from "ethers";
import { num } from "starknet";
import { StarknetKeyPair } from "../lib";

const owner = new StarknetKeyPair(1n);

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

calculate_account_signature_with_eth();
