////////////////////////////////////////////////////////////////////////////////////////////
// Instructions:
// - Setup `.env` file with all 3 variables: ADDRESS, PRIVATE_KEY, and ADDRESS
// - Fill in the privateKey2 variable
// - Run the script using the command: `yarn tsc && node --loader ts-node/esm scripts/multisig-change-threshold.ts`
////////////////////////////////////////////////////////////////////////////////////////////
import "dotenv/config";
import { RPC } from "starknet";
import { ArgentAccount, LegacyMultisigKeyPair, LegacyMultisigSigner, ensureSuccess, manager } from "../lib";

const privateKey2 = "";

// You shouldn't modify anything below this line
const contractAddress = process.env.ADDRESS;
const privateKey1 = process.env.PRIVATE_KEY;
const newThreshold = 1;

if (!contractAddress || !privateKey1 || !privateKey2) {
  console.error("Please set the ADDRESS, PRIVATE_KEY environment variables, and fill in the privateKey2 variable");
  process.exit(1);
}

const signer1 = new LegacyMultisigKeyPair(privateKey1);
const signer2 = new LegacyMultisigKeyPair(privateKey2);

const signer = new LegacyMultisigSigner([signer1, signer2]);
const account = new ArgentAccount(manager, contractAddress, signer, "1", RPC.ETransactionVersion.V3);
const accountContract = await manager.loadContract(contractAddress);

// This script only works with this classHash
if (accountContract.classHash !== "0x6e150953b26271a740bf2b6e9bca17cc52c68d765f761295de51ceb8526ee72") {
  console.error("Invalid class hash");
  process.exit(1);
}

accountContract.connect(account);
const { transaction_hash: txHash } = await ensureSuccess(await accountContract.change_threshold(newThreshold));
console.log(`Threshold successfully updated to ${newThreshold}, transaction hash: ${txHash}`);
