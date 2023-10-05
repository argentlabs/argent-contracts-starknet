import "dotenv/config";
import { Account, num } from "starknet";
import { getChangeOwnerMessageHash, KeyPair, loadContract, provider, signChangeOwnerMessage } from "../tests/lib";

const accountAddress = "0x000000000000000000000000000000000000000000000000000000000000000";
const accountContract = await loadContract(accountAddress);

const owner: bigint = await accountContract.get_owner();
const ownerSigner = new KeyPair(1000000000000000000000000000000000000000000000000000000000000000000000000000n);

if (owner !== ownerSigner.publicKey) {
  throw new Error(`onchain owner ${owner} not the same as expected ${ownerSigner.publicKey}`);
}

// local signing:
// const newOwner = new KeyPair(100000000000000000000000000000000000000000000000000000000000000000000000000n);
// const newOwnerPublicKey = newOwner.publicKey;
// const [r, s] = await signChangeOwnerMessage(accountContract.address, owner, newOwner, provider);

// remote signing:
const newOwnerPublicKey = "0x000000000000000000000000000000000000000000000000000000000000000";
console.log("messageHash:", await getChangeOwnerMessageHash(accountContract.address, owner, provider)); // share to backend
const [r, s] = [1, 2]; // fill with values from backend

console.log("r:", r);
console.log("s:", s);

const account = new Account(provider, accountAddress, ownerSigner, "1");
accountContract.connect(account);

console.log("Owner before", num.toHex(await accountContract.get_owner()));
console.log("Changing to ", num.toHex(newOwnerPublicKey));

const response = await accountContract.change_owner(newOwnerPublicKey, r, s);
await provider.waitForTransaction(response.transaction_hash);

console.log("Owner after ", num.toHex(await accountContract.get_owner()));
