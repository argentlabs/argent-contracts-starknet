////////////////////////////////////////////////////////////////////////////////////////////
// This script will generate the parameters needed to change the owner of an Argent account.
// Note that the account will be bricked after the owner change.
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
import { shortString } from "starknet";
import { StarknetKeyPair, manager, signOwnerAliveMessage } from "../lib";
const chainId = await manager.getChainId();
const newOwnerKeyPair = new StarknetKeyPair();
const validUntil = (await manager.getCurrentTimestamp()) + 60 * 60; // Valid for 1h
const signerAliveSignature = await signOwnerAliveMessage(accountAddress, newOwnerKeyPair, chainId, validUntil);
console.log("account:", accountAddress);
console.log("chainId:", shortString.decodeShortString(chainId));
console.log("Parameters for owner change:");
console.log("  signerAliveSignature:  ", JSON.stringify(signerAliveSignature));
console.log("Warning: Using these parameters will make your account unrecoverable.");
