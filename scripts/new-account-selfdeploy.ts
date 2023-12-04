import { hash, CallData } from "starknet";
import { provider, KeyPair, deployer, getEthBalance } from "../tests-integration/lib";

const prodClassHash = "0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003";
const newClassHash = "0x28463df0e5e765507ae51f9e67d6ae36c7e5af793424eccc9bc22ad705fc09d";

/////////// Select classhash here: //////////
const classHashToUse = newClassHash;
/////////////////////////////////////////////

const ethBalance = await getEthBalance(deployer.address);
console.log(`eth balance: ${ethBalance}`);
if (ethBalance == 0n) {
  throw new Error("eth balance is 0");
}

const pubKey = BigInt(await deployer.signer.getPubKey());
const salt = pubKey;
const constructorCalldata = CallData.compile({ owner: pubKey, guardian: 0n });
const contractAddress = hash.calculateContractAddressFromHash(salt, classHashToUse, constructorCalldata, 0);
if (contractAddress != deployer.address) {
  throw new Error("calculated address doesn't match deployer address");
}
const { transaction_hash } = await deployer.deploySelf(
  {
    classHash: newClassHash,
    constructorCalldata,
    addressSalt: salt,
  },
  { maxFee: ethBalance },
);
console.log(`transaction_hash: ${transaction_hash}`);
await provider.waitForTransaction(transaction_hash);
