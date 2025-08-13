import { CallData, hash } from "starknet";
import { deployer, manager } from "../lib";

const prodClassHash = "0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003";
const newClassHash = "0x2fadbf77a721b94bdcc3032d86a8921661717fa55145bccf88160ee2a5efcd1";

/////////// Select classhash here: //////////
const classHashToUse = newClassHash;
/////////////////////////////////////////////

const strkBalance = await manager.tokens.strkBalance(deployer.address);
console.log(`strk balance: ${strkBalance}`);
if (strkBalance == 0n) {
  throw new Error("strk balance is 0");
}

const pubKey = BigInt(await deployer.signer.getPubKey());
const salt = pubKey;
const constructorCalldata = CallData.compile({ owner: pubKey, guardian: 0n });
const contractAddress = hash.calculateContractAddressFromHash(salt, classHashToUse, constructorCalldata, 0);
if (contractAddress != deployer.address) {
  throw new Error("calculated address doesn't match deployer address");
}
const { transaction_hash } = await deployer.deploySelf({
  classHash: newClassHash,
  constructorCalldata,
  addressSalt: salt,
});
console.log(`transaction_hash: ${transaction_hash}`);
await manager.waitForTx(transaction_hash);
