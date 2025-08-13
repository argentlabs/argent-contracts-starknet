import "dotenv/config";
import { Account, num } from "starknet";
import { StarknetKeyPair, getOwnerAliveMessageHash, manager, starknetSignatureType } from "../lib";

/// To use this script, fill the following three values:
/// - accountAddress: the address of the account to change owner
/// - ownerSigner: the private key of the current owner
/// - newOwnerPublicKey: the public key of the new owner
/// In case you also own the private key of the new owner, you can use the local signing code instead.
/// Then run the command: `yarn ts-node scripts/change-owner.ts`

const accountAddress = "0x000000000000000000000000000000000000000000000000000000000000000";
const ownerSigner = new StarknetKeyPair(1000000000000000000000000000000000000000000000000000000000000000000000000000n);
const newOwnerPublicKey = "0x000000000000000000000000000000000000000000000000000000000000000";

const accountContract = await manager.loadContract(accountAddress);
const owner: bigint = await accountContract.get_owner();
const account = new Account(manager, accountAddress, ownerSigner, "1");
accountContract.connect(account);
const chainId = await manager.getChainId();
const validUntil = (await manager.getCurrentTimestamp()) + 60 * 60; // Valid 1h

if (owner !== ownerSigner.publicKey) {
  throw new Error(`onchain owner ${owner} not the same as expected ${ownerSigner.publicKey}`);
}

// local signing:
// const newOwner = new StarknetKeyPair(100000000000000000000000000000000000000000000000000000000000000000000000000n);
// const newOwnerPublicKey = newOwner.publicKey;
// if (BigInt(newOwnerPublicKey) !== newOwner.publicKey) {
//   throw new Error(`new owner public key ${newOwnerPublicKey} != derived ${newOwner.publicKey}`);
// }
// const starknetSignature = await signChangeOwnerMessage(accountContract.address, newOwner, chainId, validUntil);

// remote signing:
// share to backend
console.log(
  "messageHash:",
  await getOwnerAliveMessageHash(accountContract.address, chainId, ownerSigner.guid, validUntil),
);
const [r, s] = [1, 2]; // fill with values from backend

console.log("r:", r);
console.log("s:", s);

console.log("Owner before", num.toHex(await accountContract.get_owner()));
console.log("Changing to ", num.toHex(newOwnerPublicKey));

const response = await accountContract.change_owner(starknetSignatureType(newOwnerPublicKey, r, s));
await manager.waitForTx(response.transaction_hash);

console.log("Owner after ", num.toHex(await accountContract.get_owner()));
