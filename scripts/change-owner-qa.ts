////////////////////////////////////////////////////////////////////////////////////////////
// This script will generate the parameters needed to change the owner of an Argent account.
// Note the the account will be bricked after the owner change.
// Instructions:
// - Setup `.env` file with the RPC_URL variable according the network you want to use.
//   For instance for goerli network you can use this:
//   RPC_URL=https://api.hydrogen.argent47.net/v1/starknet/goerli/rpc/v0.6
// - Configure account address here:
const accountAddress = "0x064645274c31f18081e1a6b6748cfa513e59deda120a308e705cc66c32557030";
// - Run the command: `yarn tsc && node --loader ts-node/esm scripts/change-owner-qa.ts`
////////////////////////////////////////////////////////////////////////////////////////////

// No need to change anything below this

import "dotenv/config";
import { num, shortString } from "starknet";
import { StarknetKeyPair, manager, signChangeOwnerMessage } from "../lib";
const chainId = await manager.getChainId();
const newOwnerKeyPair = new StarknetKeyPair();
const validUntil = (await manager.getCurrentTimestamp()) + 60 * 60; // Valid for 1h
const [r, s] = await signChangeOwnerMessage(accountAddress, newOwnerKeyPair, chainId, validUntil);
console.log("account:", accountAddress);
console.log("chainId:", shortString.decodeShortString(chainId));
console.log("Parameters to replace_all_owners_with_one:");
console.log("  new_owner:  ", num.toHex(newOwnerKeyPair.publicKey));
console.log("  signature_r:", num.toHex(r));
console.log("  signature_s:", num.toHex(s));
console.log("  signature_expiration:", validUntil);
console.log("Warning: Using this parameters will make you account unrecoverable.");
