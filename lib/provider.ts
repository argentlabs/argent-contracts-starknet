import dotenv from "dotenv";
import { RpcProvider } from "starknet";
import { WithContracts } from "./contracts";
import { WithDevnet, devnetBaseUrl } from "./devnet";
import { WithTokens } from "./tokens";

dotenv.config({ override: true });

const Provider = WithTokens(WithDevnet(WithContracts(RpcProvider)));

export const provider = new Provider({ nodeUrl: process.env.RPC_URL || `${devnetBaseUrl}` });

console.log("Provider:", provider.channel.nodeUrl);
