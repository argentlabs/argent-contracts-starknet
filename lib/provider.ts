import dotenv from "dotenv";
import { RpcProvider } from "starknet";
import { WithDevnet, devnetBaseUrl } from "./devnet";

dotenv.config({ override: true });

const Provider = WithDevnet(RpcProvider);

export const provider = new Provider({ nodeUrl: process.env.RPC_URL || `${devnetBaseUrl}` });

console.log("Provider:", provider.channel.nodeUrl);
