import { num, hash, CallData } from "starknet";
import { StarknetKeyPair } from "../tests-integration/lib";

const prodClassHash = "0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003";
const newClassHash = "0x2fadbf77a721b94bdcc3032d86a8921661717fa55145bccf88160ee2a5efcd1";

/////////// Select classhash here: //////////
const classHashToUse = newClassHash;
/////////////////////////////////////////////

const newKeyPair = new StarknetKeyPair();
const salt = newKeyPair.publicKey;
const constructorCalldata = CallData.compile({ owner: newKeyPair.publicKey, guardian: 0n });
const accountAddress = hash.calculateContractAddressFromHash(salt, classHashToUse, constructorCalldata, 0);

console.log(`\nGenerated account details:`);
console.log(`ADDRESS=${accountAddress}`);
console.log(`PRIVATE_KEY=${num.toHex(newKeyPair.privateKey)}`);
console.log(`classHash:${classHashToUse}`);
console.log(`salt: (public key)\n`);
