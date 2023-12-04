import { num, hash, CallData } from "starknet";
import { KeyPair } from "../tests-integration/lib";

const prodClassHash = "0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003";
const newClassHash = "0x28463df0e5e765507ae51f9e67d6ae36c7e5af793424eccc9bc22ad705fc09d";

/////////// Select classhash here: //////////
const classHashToUse = newClassHash;
/////////////////////////////////////////////

const newKeyPair = new KeyPair();
const salt = newKeyPair.publicKey;
const constructorCalldata = CallData.compile({ owner: newKeyPair.publicKey, guardian: 0n });
const accountAddress = hash.calculateContractAddressFromHash(salt, classHashToUse, constructorCalldata, 0);

console.log(`\nGenerated account details:`);
console.log(`ADDRESS=${accountAddress}`);
console.log(`PRIVATE_KEY=${num.toHex(newKeyPair.privateKey)}`);
console.log(`classHash:${classHashToUse}`);
console.log(`salt: (public key)\n`);
